#!/bin/bash
# Makes sure the project and the README name the version being released.
#
#   scripts/check-version.sh 1.0.0
#
# Fails (exit 1) unless every MARKETING_VERSION in Loadout.xcodeproj/project.pbxproj is
# <version> and README.md mentions it (and names no other x.y.z version).
# scripts/make-dmg.sh runs this first.
set -euo pipefail

version="${1:-}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 <version>   e.g. $0 1.0.0" >&2
    exit 64
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
problems=0
fail() { echo "check-version: $*" >&2; problems=$((problems + 1)); }

while read -r found; do
    [[ "$found" == "$version" ]] || fail "Loadout.xcodeproj/project.pbxproj has MARKETING_VERSION = $found, not $version."
done < <(grep -o 'MARKETING_VERSION = [^;]*' Loadout.xcodeproj/project.pbxproj | sed 's/.*= //' | sort -u)

grep -qF "$version" README.md || fail "README.md doesn't mention $version."
while IFS=: read -r line found; do
    [[ "$found" == "$version" ]] && continue
    fail "README.md:$line still names $found (releasing $version)."
done < <(grep -n -o -E '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+([^0-9.]|$)' README.md \
         | sed -E 's/^([0-9]+):[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1:\2/')

if (( problems > 0 )); then
    echo "check-version: $problems problem(s). Update them for $version before releasing." >&2
    exit 1
fi
echo "check-version: Loadout $version is named in the project and README.md."
