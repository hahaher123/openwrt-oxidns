#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Static validation for the openwrt-oxidns repository.
#
# Runs without an OpenWrt tree, so it can be used in CI and locally. It checks
# the package metadata, the delivered file set, shell/UCI/YAML syntax and - if
# the network is reachable - that PKG_HASH and PKG_VERSION still match the
# upstream OxiDNS release.
#
# Usage:
#   sh scripts/validate.sh              # full check (needs network)
#   OXIDNS_OFFLINE=1 sh scripts/validate.sh
#   OXIDNS_PROXY=http://127.0.0.1:7890 sh scripts/validate.sh

set -eu

PKG_DIR="net/oxidns"
MAKE="$PKG_DIR/Makefile"
UPSTREAM_REPO="svenshi/oxidns"

OFFLINE="${OXIDNS_OFFLINE:-0}"
PROXY="${OXIDNS_PROXY:-}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/oxidns-validate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

failures=0
checks=0

ok() {
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

fail() {
	checks=$((checks + 1))
	failures=$((failures + 1))
	printf '  FAIL %s\n' "$1"
}

section() {
	printf '\n== %s ==\n' "$1"
}

# --- helpers -----------------------------------------------------------------

# extract a top level `VAR:=value` (or `VAR=value`) from the package Makefile
makevar() {
	sed -n "s/^$1:*=//p" "$MAKE" | head -n1 | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

sha256_of() {
	local h=""
	if command -v sha256sum >/dev/null 2>&1; then
		h="$(sha256sum "$1" | awk '{print $1}')"
	elif command -v shasum >/dev/null 2>&1; then
		h="$(shasum -a 256 "$1" | awk '{print $1}')"
	elif command -v openssl >/dev/null 2>&1; then
		h="$(openssl dgst -sha256 "$1" | sed 's/.*[ =]//')"
	else
		echo "no sha256 tool available" >&2
		return 1
	fi
	# GNU coreutils prefixes the digest with a backslash for file names that
	# contain one; MSYS paths trigger that too.
	printf '%s\n' "${h#\\}"
}

fetch() {
	# fetch <url> <dest>
	if command -v curl >/dev/null 2>&1; then
		if [ -n "$PROXY" ]; then
			curl -fsSL -x "$PROXY" -o "$2" "$1"
		else
			curl -fsSL -o "$2" "$1"
		fi
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		echo "no curl/wget available" >&2
		return 1
	fi
}

# --- 1. required files --------------------------------------------------------

section "required files"

for f in \
	"$MAKE" \
	"$PKG_DIR/Config.in" \
	"$PKG_DIR/files/oxidns.yaml" \
	"$PKG_DIR/files/oxidns.config" \
	"$PKG_DIR/files/oxidns.init" \
	"LICENSE" \
	"README.md"
do
	if [ -f "$f" ]; then
		ok "present: $f"
	else
		fail "missing: $f"
	fi
done

[ -f "$MAKE" ] || { printf '\n%d checks, %d failure(s)\n' "$checks" "$failures"; exit 1; }

# --- 2. package metadata ------------------------------------------------------

section "package metadata"

PKG_NAME="$(makevar PKG_NAME)"
PKG_VERSION="$(makevar PKG_VERSION)"
PKG_RELEASE="$(makevar PKG_RELEASE)"
PKG_SOURCE="$(makevar PKG_SOURCE)"
PKG_SOURCE_URL="$(makevar PKG_SOURCE_URL)"
PKG_HASH="$(makevar PKG_HASH)"
PKG_LICENSE="$(makevar PKG_LICENSE)"

for pair in \
	"PKG_NAME:$PKG_NAME" \
	"PKG_VERSION:$PKG_VERSION" \
	"PKG_RELEASE:$PKG_RELEASE" \
	"PKG_SOURCE:$PKG_SOURCE" \
	"PKG_SOURCE_URL:$PKG_SOURCE_URL" \
	"PKG_HASH:$PKG_HASH" \
	"PKG_LICENSE:$PKG_LICENSE"
do
	name="${pair%%:*}"
	value="${pair#*:}"
	if [ -n "$value" ]; then
		ok "$name is set"
	else
		fail "$name is empty"
	fi
done

# PKG_SOURCE may reference $(PKG_VERSION); expand it before comparing.
SOURCE_FILE="$(printf '%s' "$PKG_SOURCE" | sed "s/\\\$(PKG_VERSION)/$PKG_VERSION/g")"
if [ "$SOURCE_FILE" = "v$PKG_VERSION.tar.gz" ]; then
	ok "PKG_SOURCE resolves to $SOURCE_FILE"
else
	fail "PKG_SOURCE resolves to '$SOURCE_FILE', expected 'v$PKG_VERSION.tar.gz'"
fi

case "$PKG_HASH" in
	*[!0-9a-f]*) fail "PKG_HASH is not lowercase hex" ;;
	*) [ "${#PKG_HASH}" -eq 64 ] && ok "PKG_HASH is a 64 char sha256" || fail "PKG_HASH length is ${#PKG_HASH}, expected 64" ;;
esac

if grep -q 'PKG_BUILD_DEPENDS:=.*rust/host' "$MAKE"; then
	ok "PKG_BUILD_DEPENDS pulls in the Rust host toolchain"
else
	fail "PKG_BUILD_DEPENDS does not reference rust/host"
fi

if grep -q 'feeds/packages/lang/rust/rust-package.mk' "$MAKE"; then
	ok "includes feeds/packages/lang/rust/rust-package.mk"
else
	fail "does not include the OpenWrt Rust package helper"
fi

# --- 3. delivered files -------------------------------------------------------

section "install sections"

refs="$(sed -n 's/.*\.\/files\/\([A-Za-z0-9._-]*\).*/\1/p' "$MAKE" | sort -u)"
if [ -z "$refs" ]; then
	fail "no ./files/... references found in install sections"
else
	for r in $refs; do
		if [ -f "$PKG_DIR/files/$r" ]; then
			ok "installed file exists: files/$r"
		else
			fail "installed file missing: files/$r"
		fi
	done
fi

# --- 4. OpenWrt naming rules --------------------------------------------------

section "naming rules"

# Makefile package names: OpenWrt allows A-Za-z0-9_ and - in package names.
bad="$(sed -n 's/^define Package\/\([^/]*\)\/\{0,1\}.*/\1/p' "$MAKE" \
	| grep -v '^[A-Za-z0-9_-]*$' || true)"
if [ -z "$bad" ]; then
	ok "package names use only [A-Za-z0-9_-]"
else
	fail "invalid package name(s): $bad"
fi

# UCI section/option names must be A-Za-z0-9_ (a "-" breaks parsing entirely).
uci_names="$(
	sed -n -e 's/^[[:space:]]*config[[:space:]]\+\([^[:space:]]*\).*/\1/p' \
	       -e 's/^[[:space:]]*option[[:space:]]\+\([^[:space:]]*\).*/\1/p' \
	       -e 's/^[[:space:]]*list[[:space:]]\+\([^[:space:]]*\).*/\1/p' \
	       -e 's/^[[:space:]]*config[[:space:]]\+[^[:space:]]\+[[:space:]]\+\([^[:space:]]*\).*/\1/p' \
		"$PKG_DIR/files/oxidns.config" | tr -d "'\""
)"
bad="$(printf '%s\n' "$uci_names" | grep -v '^[A-Za-z0-9_]\+$' || true)"
if [ -z "$bad" ] && [ -n "$uci_names" ]; then
	ok "UCI sections/options use only [A-Za-z0-9_]"
else
	fail "invalid or missing UCI names: $(printf '%s' "$bad" | tr '\n' ' ')"
fi

# --- 5. file syntax -----------------------------------------------------------

section "file syntax"

for f in "$PKG_DIR/files/oxidns.init" scripts/validate.sh; do
	if [ -f "$f" ]; then
		if sh -n "$f" 2>"$WORK/sh.err"; then
			ok "shell syntax: $f"
		else
			fail "shell syntax: $f ($(cat "$WORK/sh.err"))"
		fi
	fi
done

if grep -q '#!/bin/sh /etc/rc.common' "$PKG_DIR/files/oxidns.init"; then
	ok "init script uses the OpenWrt rc.common shebang"
else
	fail "init script shebang is not #!/bin/sh /etc/rc.common"
fi

if grep -q 'USE_PROCD=1' "$PKG_DIR/files/oxidns.init"; then
	ok "init script is a procd service"
else
	fail "init script does not set USE_PROCD=1"
fi

# YAML forbids tab indentation.
if grep -q "$(printf '\t')" "$PKG_DIR/files/oxidns.yaml"; then
	fail "files/oxidns.yaml contains tab characters"
else
	ok "files/oxidns.yaml has no tabs"
fi

if grep -q 'root: "/usr/share/oxidns/webui"' "$PKG_DIR/files/oxidns.yaml"; then
	ok "default config points the WebUI at /usr/share/oxidns/webui"
else
	fail "default config does not point the WebUI at /usr/share/oxidns/webui"
fi

# --- 6. line endings ----------------------------------------------------------

section "line endings"

crlf=""
for f in "$MAKE" "$PKG_DIR/Config.in" "$PKG_DIR/files/oxidns.yaml" \
	"$PKG_DIR/files/oxidns.config" "$PKG_DIR/files/oxidns.init" \
	scripts/validate.sh .gitattributes
do
	[ -f "$f" ] || continue
	if LC_ALL=C grep -q "$(printf '\r')" "$f" 2>/dev/null; then
		crlf="$crlf $f"
	fi
done
if [ -z "$crlf" ]; then
	ok "no CR characters in delivered text files"
else
	fail "CRLF line endings found in:$crlf"
fi

if [ -f .gitattributes ]; then
	ok ".gitattributes is present"
else
	fail ".gitattributes is missing (git on Windows will inject CRLF)"
fi

# --- 7. upstream consistency --------------------------------------------------

section "upstream consistency"

if [ "$OFFLINE" = "1" ]; then
	printf '  skip network checks (OXIDNS_OFFLINE=1)\n'
else
	TARBALL="$WORK/$SOURCE_FILE"
	if fetch "$PKG_SOURCE_URL/$SOURCE_FILE" "$TARBALL" 2>"$WORK/dl.err"; then
		ok "downloaded $PKG_SOURCE_URL/$SOURCE_FILE"

		actual="$(sha256_of "$TARBALL")"
		if [ "$actual" = "$PKG_HASH" ]; then
			ok "PKG_HASH matches the upstream tarball"
		else
			fail "PKG_HASH mismatch: upstream=$actual, Makefile=$PKG_HASH"
		fi

		root="$(tar -tzf "$TARBALL" 2>/dev/null | head -n1)"
		if [ "$root" = "$PKG_NAME-$PKG_VERSION/" ]; then
			ok "tarball top level dir is $root (matches PKG_BUILD_DIR)"
		else
			fail "tarball top level dir is '$root', expected '$PKG_NAME-$PKG_VERSION/'"
		fi

		# cross-check the version declared in Cargo.toml
		if tar -xzOf "$TARBALL" "$PKG_NAME-$PKG_VERSION/Cargo.toml" >"$WORK/Cargo.toml" 2>/dev/null; then
			cargo_version="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$WORK/Cargo.toml" | head -n1)"
			if [ "$cargo_version" = "$PKG_VERSION" ]; then
				ok "Cargo.toml version matches PKG_VERSION ($cargo_version)"
			else
				fail "Cargo.toml version is '$cargo_version', PKG_VERSION is '$PKG_VERSION'"
			fi
		else
			fail "Cargo.toml not found inside the tarball"
		fi
	else
		fail "could not download $PKG_SOURCE_URL/$SOURCE_FILE ($(cat "$WORK/dl.err" 2>/dev/null))"
	fi

	# releases API: report how far behind the package is (informational)
	if fetch "https://api.github.com/repos/$UPSTREAM_REPO/releases/latest" "$WORK/release.json" 2>/dev/null; then
		latest="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' "$WORK/release.json" | head -n1)"
		if [ "$latest" = "$PKG_VERSION" ]; then
			ok "package tracks the latest upstream release ($latest)"
		else
			printf '  note  upstream latest release is %s, this package builds %s\n' "$latest" "$PKG_VERSION"
		fi
	fi
fi

# --- summary ------------------------------------------------------------------

printf '\n%d checks, %d failure(s)\n' "$checks" "$failures"

[ "$failures" -eq 0 ] || exit 1
