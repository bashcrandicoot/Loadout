#!/bin/bash
# Makes sure every place that names the current Loadout version names the one being built.
#
#   scripts/check-version.sh 1.0.1             # test builds (scripts/make-dmg.sh runs this)
#   scripts/check-version.sh --release 1.0.1   # a real release (scripts/make-appcast.sh runs this)
#
# Always fails (exit 1) unless:
#   - every MARKETING_VERSION in Loadout.xcodeproj/project.pbxproj (app and test targets) is <version>
#   - README.md names no other x.y.z version
# With --release it also needs README.md to say "Current version: **<version>**". Loadout is
# a beta with no release yet, so that line isn't in the README until the first release
# (docs/RELEASING.md, step 2).
set -euo pipefail

release=0
if [[ "${1:-}" == "--release" ]]; then release=1; shift; fi
version="${1:-}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 [--release] <version>   e.g. $0 --release 1.0.1" >&2
    exit 64
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
problems=0
fail() { echo "check-version: $*" >&2; problems=$((problems + 1)); }

# 1. The Xcode project.
while read -r found; do
    [[ "$found" == "$version" ]] || fail "Loadout.xcodeproj/project.pbxproj has MARKETING_VERSION = $found, not $version."
done < <(grep -o 'MARKETING_VERSION = [^;]*' Loadout.xcodeproj/project.pbxproj | sed 's/.*= //' | sort -u)

# 2. A release must be named in the README...
if (( release )); then
    grep -qF "Current version: **$version**" README.md \
        || fail "README.md doesn't say \"Current version: **$version**\"."
fi

# 3. ...and the README must never name another version.
while IFS=: read -r line found; do
    [[ "$found" == "$version" ]] && continue
    fail "README.md:$line still names $found (building $version)."
done < <(grep -n -o -E '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+([^0-9.]|$)' README.md \
         | sed -E 's/^([0-9]+):[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1:\2/')

if (( problems > 0 )); then
    echo "check-version: $problems problem(s). Update them for $version first (docs/RELEASING.md, step 2)." >&2
    exit 1
fi
if (( release )); then
    echo "check-version: Loadout $version is named in the project and README.md, ready to release."
else
    echo "check-version: Loadout $version is the project version and README.md names no other."
fi
