#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Offline regression test for scripts/build-sdk.sh.
#
# The real script needs a Linux box, ~40 GB and hours of Rust compilation. This
# test stubs out everything that touches the network or the compiler (curl,
# tar, make, scripts/feeds) and only exercises the control flow that has
# actually broken before:
#
#   1. the packages feed must be repointed away from the commit the release SDK
#      pins it to, otherwise rust is too old for OxiDNS' dependency tree
#   2. a restored build cache pre-creates the SDK directory before the script
#      runs, and that must not stop the SDK from being unpacked
#   3. a too-old rust in the feed must fail in seconds with a usable message,
#      not after an hour of building rustc
#
# No network access, no writes outside a temporary directory.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/build-sdk.sh"

SDK_VERSION="$(sed -n 's/^SDK_VERSION="\(.*\)"/\1/p' "$SCRIPT" | head -n1)"
[ -n "$SDK_VERSION" ] || { echo "cannot read the default SDK version from $SCRIPT" >&2; exit 1; }
SDK_ARCHIVE="openwrt-sdk-$SDK_VERSION-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
SDK_DIR="openwrt-sdk-$SDK_VERSION-x86-64_gcc-14.3.0_musl.Linux-x86_64"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/oxidns-buildtest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
STUB="$WORK/stub"
mkdir -p "$STUB/bin" "$WORK/run"

# ---------------------------------------------------------------- stub curl --
cat > "$STUB/bin/curl" <<'EOF'
#!/bin/sh
# curl -fsSL <url>                   -> print the SDK directory listing
# curl -fL --retry 3 -o <f> <url>    -> write a stand-in archive
out=""
while [ $# -gt 0 ]; do
	case "$1" in
		-o) out="$2"; shift 2 ;;
		-*) shift ;;
		*) shift ;;
	esac
done
if [ -n "$out" ]; then
	printf 'stub sdk archive\n' > "$out" || exit 1
	exit 0
fi
printf '<a href="%s">x</a>\n' "$STUB_SDK_ARCHIVE"
EOF

# ----------------------------------------------------------------- stub tar --
cat > "$STUB/bin/tar" <<'EOF'
#!/bin/sh
# tar --zstd -xf <archive> -C <workdir> -> create the fake SDK tree
file=""
dest="."
while [ $# -gt 0 ]; do
	case "$1" in
		-C) dest="$2"; shift 2 ;;
		-*) shift ;;
		*) file="$1"; shift ;;
	esac
done
base="$(basename "$file")"
[ -n "$base" ] || exit 1
root="$dest/${base%.tar.zst}"

mkdir -p "$root/scripts" "$root/include" "$root/feeds/packages/lang/rust" \
	"$root/bin/packages" "$root/staging_dir" "$root/build_dir"

# A release SDK ships feeds.conf.default with every feed pinned to a commit.
cat > "$root/feeds.conf.default" <<'CONF'
src-git base https://git.openwrt.org/openwrt/openwrt.git^f0a60eee2fe051741c643ea6118718aae1ef17fb
src-git packages https://git.openwrt.org/feed/packages.git^5caa62e0bc9f7fb9b0c12a23267bceb7724214dd
src-git luci https://git.openwrt.org/project/luci.git^1287812f4be233c5dd7f7466f534fd888785caf
CONF

printf '#!/bin/sh\nexit 0\n' > "$root/scripts/feeds"
chmod +x "$root/scripts/feeds"

# Normally produced by ./scripts/feeds update; STUB_RUST_VERSION picks the case.
printf 'PKG_VERSION:=%s\nPKG_RELEASE:=2\n' "${STUB_RUST_VERSION:-1.96.0}" \
	> "$root/feeds/packages/lang/rust/Makefile"

: > "$root/.config"
exit 0
EOF

# ---------------------------------------------------------------- stub make --
cat > "$STUB/bin/make" <<'EOF'
#!/bin/sh
printf 'make %s\n' "$*" >> "$STUB_MAKE_LOG"
grep -q '^CONFIG_PACKAGE_oxidns=y' .config 2>/dev/null || \
	printf 'CONFIG_PACKAGE_oxidns=y\n' >> .config
grep -q '^CONFIG_OXIDNS_BUNDLE_FULL=y' .config 2>/dev/null || \
	printf 'CONFIG_OXIDNS_BUNDLE_FULL=y\n' >> .config
mkdir -p bin/packages/x86_64/oxidns
: > bin/packages/x86_64/oxidns/oxidns-1.5.2-r1.apk
exit 0
EOF

chmod +x "$STUB/bin/curl" "$STUB/bin/tar" "$STUB/bin/make"
PATH="$STUB/bin:/usr/bin:/bin"
export PATH
STUB_SDK_ARCHIVE="$SDK_ARCHIVE"
STUB_MAKE_LOG="$WORK/make.log"
export STUB_SDK_ARCHIVE STUB_MAKE_LOG

# ------------------------------------------------------------------ harness --
pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has() { if grep -q -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1 (no '$2' in $3)"; fi; }
hasnt() { if grep -q -- "$2" "$3" 2>/dev/null; then bad "$1 (unexpected '$2')"; else ok "$1"; fi; }

run_case() {
	# run_case <name> <rust-version> <preexisting-cache: yes|no>
	name="$1"
	cache="$3"
	RUN="$WORK/run/$name"
	OUT="$WORK/run/$name-out"
	LOG="$WORK/run/$name.log"
	rm -rf "$RUN" "$OUT"
	mkdir -p "$RUN"
	if [ "$cache" = "yes" ]; then
		# What actions/cache restores before the script runs: slices of the
		# SDK directory, but no feeds.conf.default.
		mkdir -p "$RUN/$SDK_DIR/staging_dir/host/bin" "$RUN/$SDK_DIR/build_dir/target-x86_64_musl/host"
	fi
	STUB_RUST_VERSION="$2"
	export STUB_RUST_VERSION
	: > "$STUB_MAKE_LOG"
	sh "$SCRIPT" -t x86/64 -v "$SDK_VERSION" -j 4 -w "$RUN" -o "$OUT" > "$LOG" 2>&1
	RC=$?
	SDK="$RUN/$SDK_DIR"
}

printf '\n1. fresh workdir, feed carries rust 1.96\n'
run_case t1 1.96.0 no
eq "exit status" "$RC" "0"
has "packages feed repointed to the release branch" \
	"^src-git packages https://git.openwrt.org/feed/packages.git;openwrt-${SDK_VERSION%.*}\$" \
	"$SDK/feeds.conf"
has "unrelated feeds are left pinned" 'luci.git\^1287812f4be233c5dd7f7466f534fd888785caf' "$SDK/feeds.conf"
has "rust version is reported" 'feeds/packages provides rust 1.96.0' "$LOG"
has "the package is compiled" 'package/feeds/oxidns/oxidns/compile' "$STUB_MAKE_LOG"
eq "artifact lands in -o directory" "$(ls "$OUT" 2>/dev/null | tr '\n' ' ')" "oxidns-1.5.2-r1.apk "

printf '\n2. restored build cache already created the SDK directory\n'
run_case t2 1.96.0 yes
eq "exit status" "$RC" "0"
if [ -f "$SDK/feeds.conf.default" ]; then
	ok "SDK is unpacked anyway"
else
	bad "SDK was not unpacked (extraction skipped)"
fi
has "packages feed repointed" 'openwrt-25.12' "$SDK/feeds.conf"
eq "artifact lands in -o directory" "$(ls "$OUT" 2>/dev/null | tr '\n' ' ')" "oxidns-1.5.2-r1.apk "

printf '\n3. feed carries rust 1.94, the version the 25.12.5 SDK pins\n'
run_case t3 1.94.0 no
if [ "$RC" != "0" ]; then ok "fails instead of building"; else bad "exited 0"; fi
has "names the offending version" 'rust 1.94.0 is too old' "$LOG"
has "explains the sysinfo requirement" 'sysinfo 0.39' "$LOG"
has "shows the way out" 'OXIDNS_PACKAGES_FEED' "$LOG"
hasnt "no compiler was run at all" 'compile' "$STUB_MAKE_LOG"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
