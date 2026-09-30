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
# The script repoints the feeds/packages feed from the pinned commit shipped in
# the SDK's feeds.conf.default to the matching release branch; see the comment
# above the "Repointing feed packages" line.
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

# OxiDNS 1.5.2 needs rustc >= 1.95: edition 2024 wants 1.85, and sysinfo 0.39
# (a hard dependency, see the upstream Cargo.toml) declares rust-version 1.95.
# OpenWrt 24.10 ships rust 1.94 and can therefore not build this version.
MIN_RUST_MINOR=95

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

Environment:
  OXIDNS_WORKDIR        working directory (same as -w)
  OXIDNS_PACKAGES_FEED  override the feeds/packages feed entry, e.g.
                        https://git.openwrt.org/feed/packages.git;openwrt-25.12
                        (needed if the SDK's pinned feed carries a rust too old
                        for OxiDNS; see the error message the script prints)
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

# 25.12.5 -> 25.12, used to pick the matching feed branch below.
SDK_SERIES="${SDK_VERSION%.*}"

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
# Do not test for the directory: a restored build cache recreates it (it holds
# staging_dir/, build_dir/...) long before the SDK itself is unpacked, and
# skipping the extraction would then leave no feeds.conf.default or scripts/.
if [ ! -f "$sdk_dir/feeds.conf.default" ]; then
	printf 'Extracting %s ...\n' "$sdk_url"
	if tar --zstd -xf "$sdk_file" -C "$WORKDIR" 2>/dev/null; then
		:
	else
		command -v zstd >/dev/null 2>&1 || { echo "tar lacks zstd support and no zstd binary was found" >&2; exit 1; }
		zstd -dc "$sdk_file" | tar -xf - -C "$WORKDIR"
	fi
fi

[ -f "$sdk_dir/feeds.conf.default" ] || { echo "SDK directory not found: $sdk_dir" >&2; exit 1; }

printf 'Using SDK: %s\n' "$sdk_dir"
cd "$sdk_dir"

# --- feeds -------------------------------------------------------------------

# feeds.conf must be a full copy of feeds.conf.default, otherwise the default
# feeds disappear the moment the file exists.
if [ ! -f feeds.conf ]; then
	cp feeds.conf.default feeds.conf
fi

# A release SDK pins every feed to the commit that was current when the release
# was cut. The pin inside the 25.12.5 SDK predates "rust: update to 1.96.0", so
# feeds/packages there still carries rustc 1.94 and OxiDNS cannot be built with
# it. Track the release branch for feeds/packages, exactly like a buildroot
# checkout of the same branch would.
# Override with OXIDNS_PACKAGES_FEED=<url>[;<branch>|^<commit>].
packages_feed="${OXIDNS_PACKAGES_FEED:-https://git.openwrt.org/feed/packages.git;openwrt-$SDK_SERIES}"
if grep -q "^src-git\(-full\)\{0,1\} packages[[:space:]]" feeds.conf; then
	printf 'Repointing feed packages to %s\n' "$packages_feed"
	sed -i -e "s|^src-git\(-full\)\{0,1\} packages[[:space:]].*|src-git packages $packages_feed|" feeds.conf
	grep -q "$packages_feed" feeds.conf || {
		echo "could not repoint the packages feed in feeds.conf" >&2
		exit 1
	}
fi

# This repository is a flat package layout: Makefile, Config.in and files/ all sit
# in the repo root. A feed index is built by include/scan.mk, which collects the
# candidates with
#
#   find -L $(SCAN_DIR) -mindepth 1 -maxdepth 5 -name Makefile
#
# and then normalises every hit into a package directory name with
#
#   sed -e 's#^$(SCAN_DIR)/##' -e 's#/Makefile:.*##'
#
# For a Makefile sitting in the feed root itself the first sed strips the prefix
# and leaves a bare "Makefile:...", the second one matches nothing, and the entry
# reaches the index as a malformed path that gets dropped - that is why a feed
# root Makefile never becomes a package. (find does list it; the depth option is
# not what filters it out.) Pointing src-link straight at $REPO_ROOT would
# therefore index nothing at all.
#
# So insert one directory level holding a symlink back to the repo: the link name
# becomes the package directory, and the scan sees <feed root>/oxidns/Makefile.
# find runs with -L, so the symlink is followed.
feed_root="$WORKDIR/feed"
mkdir -p "$feed_root"
if [ -e "$feed_root/oxidns" ]; then
	rm -rf "$feed_root/oxidns"
fi
ln -s "$REPO_ROOT" "$feed_root/oxidns"
if [ ! -f "$feed_root/oxidns/Makefile" ]; then
	# Windows/git-bash cannot create directory symlinks without developer mode:
	# ln -s leaves an empty directory behind. Fall back to a copy of the working
	# tree (minus .git) so the same script is usable from a local MSYS shell too.
	# On Linux - the supported build host - this branch never runs.
	rm -rf "$feed_root/oxidns"
	mkdir -p "$feed_root/oxidns"
	# Copy the working tree, skipping .git: a copy of the object store is useless
	# here and it is the only thing that would make the copy large.
	for entry in "$REPO_ROOT"/* "$REPO_ROOT"/.[!.]*; do
		[ -e "$entry" ] || continue
		case "${entry##*/}" in
			.git) continue ;;
		esac
		cp -R "$entry" "$feed_root/oxidns/"
	done
fi
[ -f "$feed_root/oxidns/Makefile" ] || {
	echo "the staging feed directory does not contain the package: $feed_root/oxidns/Makefile" >&2
	exit 1
}

if ! grep -q "src-link oxidns $feed_root" feeds.conf; then
	printf 'src-link oxidns %s\n' "$feed_root" >> feeds.conf
fi

printf 'Updating feeds ...\n'
./scripts/feeds update -a

# Fail in seconds instead of after an hour of building the Rust host toolchain.
rust_mk="feeds/packages/lang/rust/Makefile"
rust_ver=""
if [ -f "$rust_mk" ]; then
	rust_ver="$(sed -n 's/^PKG_VERSION[[:space:]]*[:?]\{0,1\}=[[:space:]]*//p' "$rust_mk" | head -n1)"
fi
rust_minor="${rust_ver#1.}"
rust_minor="${rust_minor%%.*}"
case "$rust_minor" in
	''|*[!0-9]*)
		printf 'warning: could not read the rust version from %s (got "%s")\n' "$rust_mk" "$rust_ver" >&2
		;;
	*)
		printf 'feeds/packages provides rust %s\n' "$rust_ver"
		if [ "$rust_minor" -lt "$MIN_RUST_MINOR" ]; then
			cat >&2 <<EOF

ERROR: rust $rust_ver is too old for OxiDNS.

OxiDNS depends on sysinfo 0.39, which declares rust-version 1.95, so the Rust
host toolchain must be >= 1.$MIN_RUST_MINOR. feeds/packages currently ships
$rust_ver, which happens when the feed is pinned to an old commit (release SDKs
pin their feeds).

Fix: run with a feed branch/commit new enough, e.g.

  OXIDNS_PACKAGES_FEED='https://git.openwrt.org/feed/packages.git;openwrt-25.12' \\
    sh scripts/build-sdk.sh ...

or, for that SDK, from a full buildroot checkout:
  ./scripts/feeds update packages && make package/feeds/packages/rust/host/compile
EOF
			exit 1
		fi
		;;
esac

./scripts/feeds install -a -p oxidns
./scripts/feeds install rust

# --- configuration ------------------------------------------------------------

# The SDK ships a .config for its own target: extend it, never replace it.
grep -q '^CONFIG_PACKAGE_oxidns=y' .config || cat >> .config <<EOF
CONFIG_PACKAGE_oxidns=y
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

# --- download -----------------------------------------------------------------

: > "$WORKDIR/build.log"
printf 'Full build log: %s\n' "$WORKDIR/build.log"

# Fetch both archives up front (the tag archive with the sources and the
# release archive holding the prebuilt WebUI). A digest mismatch or a missing
# release asset then fails in seconds instead of after the Rust host toolchain
# has been compiled for an hour.
printf '\nDownloading package sources and the WebUI archive ...\n'
make -j"$JOBS" package/feeds/oxidns/oxidns/download V=s >> "$WORKDIR/build.log" 2>&1 || {
	printf '\nDownload failed. Last 60 log lines:\n\n' >&2
	tail -n 60 "$WORKDIR/build.log" >&2
	printf '\nFull log: %s\n' "$WORKDIR/build.log" >&2
	exit 1
}

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

printf '\nBuilding oxidns. This can take a very long time ...\n'
build_pkg oxidns

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
