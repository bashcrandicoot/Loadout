#!/bin/bash
# Adds a new Loadout release to appcast.xml (the Sparkle update feed), signed with Loadout's
# own EdDSA private key in your login Keychain (Keychain account "loadout"; Lodge's key, under
# Sparkle's default account, is never used here).
#
#   scripts/make-appcast.sh <version> [folder-with-the-release-files]
#   scripts/make-appcast.sh 1.0.1                 # looks in build/release
#
# The folder must contain Loadout-<version>.zip (Loadout.app zipped with `ditto -c -k
# --keepParent`). Sparkle downloads the zip; the .dmg is for people downloading by hand.
# Optional release notes: Loadout-<version>.md (or .html) next to the zip.
#
# Only appcast.xml in the repo is changed. Nothing is uploaded, tagged or pushed.
# See docs/RELEASING.md for the whole release, step by step.
#
# Environment (optional):
#   SPARKLE_BIN    folder with Sparkle's generate_appcast (found automatically otherwise)
#   ED_KEY_FILE    sign with a private key file instead of the Keychain (testing only)
set -euo pipefail

REPO_URL="https://github.com/bashcrandicoot/Loadout"
KEY_ACCOUNT="loadout"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "Usage: $0 <version> [folder]   e.g. $0 1.0.1" >&2
    exit 64
fi
version="${version#v}"
folder="${2:-$ROOT/build/release}"
zip="$folder/Loadout-$version.zip"

# Refuse to sign a release the README or the project don't name yet.
"$ROOT/scripts/check-version.sh" --release "$version"
[[ -f "$zip" ]] || { echo "Can't find $zip" >&2; exit 66; }

# Find Sparkle's command-line tools (they come with the Swift package).
find_bin() {
    if [[ -n "${SPARKLE_BIN:-}" ]]; then echo "$SPARKLE_BIN"; return; fi
    local candidate
    for candidate in \
        "$ROOT"/build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin \
        /tmp/loadout-dd*/SourcePackages/artifacts/sparkle/Sparkle/bin \
        "$HOME"/Library/Developer/Xcode/DerivedData/Loadout-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
        if [[ -x "$candidate/generate_appcast" ]]; then echo "$candidate"; return; fi
    done
    echo "Fetching the Sparkle package to get its tools…" >&2
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        xcodebuild -project "$ROOT/Loadout.xcodeproj" -scheme Loadout \
        -derivedDataPath /tmp/loadout-dd-sparkle-tools -resolvePackageDependencies >/dev/null
    echo /tmp/loadout-dd-sparkle-tools/SourcePackages/artifacts/sparkle/Sparkle/bin
}
bin="$(find_bin)"
[[ -x "$bin/generate_appcast" ]] || { echo "generate_appcast not found in $bin" >&2; exit 69; }

# Sanity check: the app in the zip must be the version you said, carry Loadout's public key,
# and its build number (CFBundleVersion, which Sparkle compares) must be higher than every
# build in the feed.
check="$(mktemp -d)"
staging="$(mktemp -d)"
trap 'rm -rf "$check" "$staging"' EXIT
ditto -x -k "$zip" "$check"
plist="$check/Loadout.app/Contents/Info.plist"
[[ -f "$plist" ]] || { echo "The zip must contain Loadout.app at its top level." >&2; exit 65; }
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
if [[ "$app_version" != "$version" ]]; then
    echo "The zip contains Loadout $app_version, not $version." >&2; exit 65
fi
app_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
[[ -n "$app_key" ]] || { echo "This Loadout.app has no SUPublicEDKey, so it was built without Sparkle." >&2; exit 65; }
if [[ -z "${ED_KEY_FILE:-}" ]]; then
    keychain_key="$("$bin/generate_keys" --account "$KEY_ACCOUNT" -p 2>/dev/null || true)"
    if [[ "$keychain_key" != "$app_key" ]]; then
        echo "The Keychain key for account \"$KEY_ACCOUNT\" doesn't match the app's SUPublicEDKey." >&2
        echo "  app:      $app_key" >&2
        echo "  Keychain: ${keychain_key:-(none)}" >&2
        exit 65
    fi
fi
latest_build="$(grep -o '<sparkle:version>[^<]*' "$ROOT/appcast.xml" | sed 's/.*>//' | sort -n | tail -1 || true)"
if [[ -n "$latest_build" ]] && (( app_build <= latest_build )); then
    echo "Build number $app_build isn't higher than $latest_build, already in appcast.xml." >&2
    echo "Raise CURRENT_PROJECT_VERSION in the Loadout target and rebuild." >&2
    exit 65
fi

# generate_appcast works on a folder: give it the current feed plus just this release.
cp "$ROOT/appcast.xml" "$staging/appcast.xml"
cp "$zip" "$staging/"
for notes in "$folder/Loadout-$version".{md,html,txt}; do
    [[ -f "$notes" ]] && cp "$notes" "$staging/"
done

args=(--download-url-prefix "$REPO_URL/releases/download/v$version/"
      --link "$REPO_URL"
      --maximum-deltas 0
      --embed-release-notes)
if [[ -n "${ED_KEY_FILE:-}" ]]; then
    args+=(--ed-key-file "$ED_KEY_FILE")
else
    args+=(--account "$KEY_ACCOUNT")
fi

if [[ -n "${ED_KEY_FILE:-}" ]]; then
    echo "Signing Loadout $version (build $app_build) with the key in ${ED_KEY_FILE}…"
else
    echo "Signing Loadout $version (build $app_build) with Loadout's Sparkle key (account \"$KEY_ACCOUNT\")…"
    echo "(If macOS asks whether generate_appcast may use your Keychain, click Always Allow.)"
fi
"$bin/generate_appcast" "${args[@]}" "$staging"

# Refuse an unsigned entry: Loadout only installs updates signed with its key.
# Look anywhere in the new <item>: embedded release notes push the enclosure (which carries
# the signature) well below <sparkle:version>.
new_item() {
    awk -v b="<sparkle:version>$app_build</sparkle:version>" \
        '/<item>/{buf=""} {buf=buf $0 "\n"} /<\/item>/{if (index(buf, b)) printf "%s", buf}' "$1"
}
if ! new_item "$staging/appcast.xml" | grep -q 'sparkle:edSignature='; then
    echo "The new entry wasn't signed (does the key match SUPublicEDKey?)." >&2
    echo "appcast.xml was left unchanged." >&2
    exit 70
fi

cp "$staging/appcast.xml" "$ROOT/appcast.xml"
echo
echo "Updated appcast.xml with Loadout $version. Next: commit it, tag v$version, push the tag,"
echo "create the GitHub release with --verify-tag, then push main (docs/RELEASING.md)."
