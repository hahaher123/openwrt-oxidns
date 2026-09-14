#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build the OxiDNS packages against an official OpenWrt SDK.
#
# Requires a Linux host (or WSL) with tar, zstd, make, a C/C++ toolchain,
# ncurses headers, python3, curl and roughly 40 GB of free disk space.
#
# The first run has to compile the Rust host toolchain from source, LLVM
# included. That takes hours; it is a property of the OpenWrt Rust package
# (feeds/packages/lang/rust), not of OxiDNS. Subsequent runs reuse
# build_dir/ and only recompile what changed.
#
# Usage:
#   sh scripts/build-sdk.sh                            # x86/64, default release
#   sh scripts/build-sdk.sh -t armsr/armv8
#   sh scripts/build-sdk.sh -t x86/64 -v 25.12.5 -j 8
#   sh scripts/build-sdk.sh -o /srv/out

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TARGET="x86/64"
SDK_VERSION="25.12.5"
JOBS="$( (nproc 2>/dev/null || echo 4) )"
WORKDIR="${OXIDNS_WORKDIR:-$HOME/.cache/openwrt-oxidns}"
OUTDIR=""
SDK_BASE="https://downloads.openwrt.org/releases"

usage() {
	cat <<EOF
Usage: sh scripts/build-sdk.sh [options]

  -t <target>    OpenWrt target, e.g. x86/64, armsr/armv8, ramips/mt7621
                 (default: $TARGET)
  -v <version>   OpenWrt release to use, e.g. 25.12.5
                 (default: $SDK_VERSION)
  -j <jobs>      parallel make jobs (default: CPU count)
  -w <dir>       working directory for SDK and downloads
                 (default: \$OXIDNS_WORKDIR or $HOME/.cache/openwrt-oxidns)
  -o <dir>       copy the produced packages into this directory
  -h             show this help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-t) TARGET="$2"; shift 2 ;;
		-v) SDK_VERSION="$2"; shift 2 ;;
		-j) JOBS="$2"; shift 2 ;;
		-w) WORKDIR="$2"; shift 2 ;;
		-o) OUTDIR="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
	esac
done

case "$TARGET" in
	*/*) ;;
	*) echo "-t expects <target>/<subtarget>, e.g. x86/64" >&2; exit 1 ;;
esac

command -v tar >/dev/null 2>&1 || { echo "missing required tool: tar" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "missing required tool: curl" >&2; exit 1; }

mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"

SDK_LIST_URL="$SDK_BASE/$SDK_VERSION/targets/$TARGET/"
printf 'Looking up the SDK for OpenWrt %s / %s ...\n' "$SDK_VERSION" "$TARGET"

sdk_url="$(
	curl -fsSL "$SDK_LIST_URL" \
		| grep -o "openwrt-sdk-$SDK_VERSION-[^\"]*Linux-x86_64\.tar\.zst" \
		| sort -u | head -n1
)"
[ -n "$sdk_url" ] || { echo "no x86_64 SDK found at $SDK_LIST_URL" >&2; exit 1; }

sdk_file="$WORKDIR/$sdk_url"
if [ ! -f "$sdk_file" ]; then
	printf 'Downloading %s ...\n' "$sdk_url"
	curl -fL --retry 3 -o "$sdk_file.part" "$SDK_LIST_URL$sdk_url"
	mv "$sdk_file.part" "$sdk_file"
fi

sdk_dir="$WORKDIR/${sdk_url%.tar.zst}"
if [ ! -d "$sdk_dir" ]; then
	printf 'Extracting %s ...\n' "$sdk_url"
	if tar --zstd -xf "$sdk_file" -C "$WORKDIR" 2>/dev/null; then
		:
	else
		command -v zstd >/dev/null 2>&1 || { echo "tar lacks zstd support and no zstd binary was found" >&2; exit 1; }
		zstd -dc "$sdk_file" | tar -xf - -C "$WORKDIR"
	fi
fi

[ -d "$sdk_dir" ] || { echo "SDK directory not found: $sdk_dir" >&2; exit 1; }

printf 'Using SDK: %s\n' "$sdk_dir"
cd "$sdk_dir"

# --- feeds -------------------------------------------------------------------

# feeds.conf must be a full copy of feeds.conf.default, otherwise the default
# feeds disappear the moment the file exists.
if [ ! -f feeds.conf ]; then
	cp feeds.conf.default feeds.conf
fi

if ! grep -q "src-link oxidns $REPO_ROOT" feeds.conf; then
	printf 'src-link oxidns %s\n' "$REPO_ROOT" >> feeds.conf
fi

printf 'Updating feeds ...\n'
./scripts/feeds update -a
./scripts/feeds install -a -p oxidns
./scripts/feeds install rust

# --- configuration ------------------------------------------------------------

# The SDK ships a .config for its own target: extend it, never replace it.
grep -q '^CONFIG_PACKAGE_oxidns=y' .config || cat >> .config <<EOF
CONFIG_PACKAGE_oxidns=y
CONFIG_PACKAGE_oxidns-service=y
EOF

printf 'Preparing configuration (make defconfig) ...\n'
make defconfig

grep -q '^CONFIG_PACKAGE_oxidns=y' .config || {
	echo "CONFIG_PACKAGE_oxidns was not accepted by the build system" >&2
	exit 1
}
printf 'Feature bundle: %s\n' "$(
	sed -n 's/^CONFIG_OXIDNS_BUNDLE_\(.*\)=y/\1/p' .config | tr 'A-Z' 'a-z' | head -n1
)"

# --- build --------------------------------------------------------------------

# Build one package and keep the full log on disk. A plain "make | tee" would
# hide make's exit status behind tee's, so the status is checked explicitly.
build_pkg() {
	pkg="$1"
	printf '\n=== building %s ===\n' "$pkg"
	if make -j"$JOBS" "package/feeds/oxidns/$pkg/compile" V=s >> "$WORKDIR/build.log" 2>&1; then
		printf '%s: ok\n' "$pkg"
		return 0
	fi
	printf '\n%s failed. Last 300 log lines:\n\n' "$pkg" >&2
	tail -n 300 "$WORKDIR/build.log" >&2
	printf '\nFull log: %s\n' "$WORKDIR/build.log" >&2
	return 1
}

printf '\nBuilding oxidns + oxidns-service. This can take a very long time ...\n'
printf 'Full build log: %s\n' "$WORKDIR/build.log"
: > "$WORKDIR/build.log"
build_pkg oxidns
build_pkg oxidns-service

artefacts="$(
	find bin/packages -maxdepth 3 -type f \( -name 'oxidns*.ipk' -o -name 'oxidns*.apk' \) | sort
)"
[ -n "$artefacts" ] || {
	echo "the build finished but produced no package - see $WORKDIR/build.log" >&2
	exit 1
}

printf '\nBuilt:\n'
printf '%s\n' "$artefacts" | sed "s|^|  $sdk_dir/|"

if [ -n "$OUTDIR" ]; then
	mkdir -p "$OUTDIR"
	printf '%s\n' "$artefacts" | while read -r a; do
		cp "$a" "$OUTDIR/"
	done
	printf '\nPackages copied to %s\n' "$OUTDIR"
fi
