#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Bump this package to an upstream OxiDNS release.
#
# It reads the version from the tarball (not from the release name), recomputes
# PKG_HASH and rewrites oxidns/Makefile. Nothing is committed: review the
# diff and commit it yourself.
#
# Usage:
#   sh scripts/sync-upstream.sh                  # latest upstream release
#   sh scripts/sync-upstream.sh 1.5.2            # explicit version
#   OXIDNS_PROXY=http://127.0.0.1:7890 sh scripts/sync-upstream.sh

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKE="$REPO_ROOT/oxidns/Makefile"
UPSTREAM_REPO="svenshi/oxidns"
PROXY="${OXIDNS_PROXY:-}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/oxidns-sync.XXXXXX")"
# mktemp may hand back a Windows-style path (C:\...) when TMPDIR is a Windows
# path; GNU tar would read that as a remote "host:file" spec. cd+pwd normalises
# it to a shell path.
WORK="$(cd "$WORK" && pwd)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

fetch() {
	# fetch <url> <dest>
	#
	# Runs in a subshell that cd's into the destination directory and downloads
	# to "./<name>". That keeps the path relative, which matters when the only
	# curl around is the Windows one (it understands C:\... but not MSYS
	# /c/... paths) while tar wants the opposite.
	dir="$(dirname "$2")"
	base="$(basename "$2")"
	(
		cd "$dir" || exit 1
		if command -v curl >/dev/null 2>&1; then
			if [ -n "$PROXY" ]; then
				curl -fsSL -x "$PROXY" -o "./$base" "$1"
			else
				curl -fsSL -o "./$base" "$1"
			fi
		else
			if [ -n "$PROXY" ]; then
				http_proxy="$PROXY" https_proxy="$PROXY" wget -q -O "./$base" "$1"
			else
				wget -q -O "./$base" "$1"
			fi
		fi
	)
}

sha256_of() {
	local h=""
	if command -v sha256sum >/dev/null 2>&1; then
		h="$(sha256sum "$1" | awk '{print $1}')"
	elif command -v shasum >/dev/null 2>&1; then
		h="$(shasum -a 256 "$1" | awk '{print $1}')"
	else
		h="$(openssl dgst -sha256 "$1" | sed 's/.*[ =]//')"
	fi
	# GNU coreutils prefixes the digest with a backslash for file names that
	# contain one; MSYS paths trigger that too.
	printf '%s\n' "${h#\\}"
}

version="${1:-}"
if [ -z "$version" ]; then
	printf 'Querying the latest %s release...\n' "$UPSTREAM_REPO"
	fetch "https://api.github.com/repos/$UPSTREAM_REPO/releases/latest" "$WORK/release.json"
	version="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' "$WORK/release.json" | head -n1)"
	[ -n "$version" ] || { echo "could not determine the latest release tag" >&2; exit 1; }
fi

tarball="$WORK/v$version.tar.gz"
url="https://github.com/$UPSTREAM_REPO/archive/refs/tags/v$version.tar.gz"

printf 'Downloading %s\n' "$url"
fetch "$url" "$tarball"

cargo_version="$(tar -xzOf "$tarball" "oxidns-$version/Cargo.toml" 2>/dev/null \
	| sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' | head -n1)"
if [ -n "$cargo_version" ] && [ "$cargo_version" != "$version" ]; then
	echo "tag v$version contains Cargo.toml version $cargo_version - refusing to guess" >&2
	exit 1
fi

hash="$(sha256_of "$tarball")"
old_version="$(sed -n 's/^PKG_VERSION:=//p' "$MAKE" | head -n1)"
old_hash="$(sed -n 's/^PKG_HASH:=//p' "$MAKE" | head -n1)"

if [ "$old_version" = "$version" ] && [ "$old_hash" = "$hash" ]; then
	printf 'Already up to date: %s (%s)\n' "$version" "$hash"
	exit 0
fi

sed -e "s/^PKG_VERSION:=.*/PKG_VERSION:=$version/" \
	-e "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" \
	-e "s/^PKG_HASH:=.*/PKG_HASH:=$hash/" \
	"$MAKE" > "$WORK/Makefile.new"
mv "$WORK/Makefile.new" "$MAKE"
chmod 644 "$MAKE"

printf '\nUpdated %s\n' "$MAKE"
printf '  PKG_VERSION %s -> %s\n' "$old_version" "$version"
printf '  PKG_HASH    %s -> %s\n' "$old_hash" "$hash"
printf '\nNext: sh scripts/validate.sh && git commit -am "oxidns: update to %s"\n' "$version"
