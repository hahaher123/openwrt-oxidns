#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Verify that the built .apk packages really carry the version the release is
# about to be tagged with.
#
# Why this exists: the reusable build workflow checks out github.sha, which is
# the commit that *triggered* the run - not the commit the probe job pushed
# afterwards. The build therefore compiled the previous version while the
# publish job tagged the result with the new one, and the release claimed
# v1.6.0 while shipping a 1.5.2 package. This script turns that silent
# mismatch into a hard failure.
#
# Usage:
#   sh scripts/check-apk-version.sh <tag-or-version> <apk> [<apk> ...]
#
# <tag-or-version> accepts v1.6.0-r1, 1.6.0-r1, v1.6.0 or 1.6.0; the leading
# "v" is optional and a missing release part defaults to r1.

set -eu

if [ "$#" -lt 2 ]; then
	echo "usage: $0 <tag-or-version> <apk> [<apk> ...]" >&2
	exit 2
fi

want_raw="$1"
shift

# Normalise "v1.6.0-r1" / "1.6.0" / "1.6.0-r1" to the bare "1.6.0-r1" form.
# A missing release part defaults to r1, matching the Makefile's
# PKG_RELEASE:=1 reset on every upstream version bump.
want="$(printf '%s' "$want_raw" | sed -e 's/^v//')"
case "$want" in
	*-r*) ;;
	*) want="$want-r1" ;;
esac

echo "expecting package version: $want"

failures=0
checked=0
skip_content=0

for apk in "$@"; do
	checked=$((checked + 1))
	base="$(basename "$apk")"

	# 1) the file name must end in -<version>.apk
	case "$base" in
		*"-$want.apk")
			echo "  ok   $base: file name carries $want"
			;;
		*)
			echo "  FAIL $base: file name does not end in -$want.apk" >&2
			failures=$((failures + 1))
			continue
			;;
	esac

	# 2) the metadata inside the package must agree.
	#
	# apk-tools 3 stores a package as an ADB container: the ASCII magic "ADBd",
	# then a bare deflate stream (no zlib/gzip wrapper, so wbits=-15). After
	# decompressing, the payload starts with "ADB.pckg", a u64 (payload length)
	# and a u32 - so the metadata fields begin at offset 20, as a flat sequence
	# of <length><content> pairs in the order
	#   name, version, description, arch, ...
	# The length prefix width depends on the content length (apk-tools
	# src/adb.c, adb_w_blob_vec): <=0xff -> 1 byte, <=0xffff -> 2 bytes, larger
	# -> 4 bytes, little-endian. Only name and version are read here; both are
	# far shorter than 255 bytes, so a single-byte prefix is always correct for
	# them. (The description that follows is NOT, which is why the parser stops
	# after the version instead of walking the whole record.)
	python_bin=""
	for cand in python3 python; do
		if command -v "$cand" >/dev/null 2>&1; then
			python_bin="$cand"
			break
		fi
	done

	if [ -z "$python_bin" ]; then
		echo "  warn $base: no python available, content NOT verified" >&2
		skip_content=$((skip_content + 1))
		continue
	fi

	got="$("$python_bin" - "$apk" <<'PY'
import sys, zlib

path = sys.argv[1]
data = open(path, 'rb').read()

if not data.startswith(b'ADB'):
    # apk-tools 2 style (ipk) or something else entirely.
    print('NOT_ADB')
    sys.exit(0)

blob = None
for start in range(4, min(len(data), 8192)):
    try:
        cand = zlib.decompressobj(-15).decompress(data[start:])
    except Exception:
        continue
    if cand.startswith(b'ADB.pckg'):
        blob = cand
        break

if blob is None:
    print('NO_CONTROL')
    sys.exit(0)

# name and version sit at offset 20, each as a single-byte length + content.
try:
    nlen = blob[20]
    name = blob[21:21 + nlen]
    vlen_pos = 21 + nlen
    vlen = blob[vlen_pos]
    version = blob[vlen_pos + 1:vlen_pos + 1 + vlen]
except IndexError:
    print('TRUNCATED')
    sys.exit(0)

print(version.decode('utf-8', 'replace'))
PY
)"

	case "$got" in
		"$want")
			echo "  ok   $base: metadata says $got"
			;;
		NOT_ADB)
			echo "  warn $base: not an ADB container, file name check only" >&2
			skip_content=$((skip_content + 1))
			;;
		*)
			echo "  FAIL $base: metadata says '$got', expected '$want'" >&2
			failures=$((failures + 1))
			;;
	esac
done

if [ "$skip_content" -gt 0 ]; then
	echo "  warn $skip_content package(s) were not content-verified" >&2
fi

if [ "$failures" -eq 0 ]; then
	printf '%d package(s) checked, version %s confirmed\n' "$checked" "$want"
	exit 0
fi

printf '%d package(s) checked, %d failure(s)\n' "$checked" "$failures" >&2
exit 1
