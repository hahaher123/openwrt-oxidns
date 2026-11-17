#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Print the latest stable upstream release version (no leading 'v').
#
# Why not the releases/latest API:
#   Anonymous GitHub API calls are capped at 60/hour per source IP. GitHub
#   Actions runners share their egress IP, so the scheduled upstream-watch
#   probe intermittently got HTTP 403 (observed 2026-11-16) and went red even
#   though upstream had not changed. curl's --retry does not cover 403 and
#   -f turns it into exit 22, so the retry policy could not save it.
#
#   git ls-remote uses the git protocol against github.com, which has no such
#   anonymous API quota and needs no token. Keeping secrets out of the
#   workflow file is deliberate: that file is public.
#
# Only plain vX.Y.Z tags count; pre-release tags (v1.8.0-rc1, -beta, ...) are
# ignored so a pre-release never bumps the package.
#
# Usage:
#   sh scripts/latest-upstream-version.sh [owner/repo]
# Default repo is svenshi/oxidns.

set -eu

UPSTREAM_REPO="${1:-svenshi/oxidns}"

version="$(
	git ls-remote --tags --refs "https://github.com/$UPSTREAM_REPO.git" 'refs/tags/v*' 2>/dev/null \
		| sed -n 's#.*refs/tags/\([^[:space:]]*\)#\1#p' \
		| grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
		| sed 's/^v//' \
		| sort -V \
		| tail -n1
)"

if [ -z "$version" ]; then
	echo "could not determine the latest stable tag of $UPSTREAM_REPO" >&2
	exit 1
fi

printf '%s\n' "$version"
