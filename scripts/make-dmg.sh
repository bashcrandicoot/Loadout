#!/bin/bash
# Makes the drag-to-install disk image for a Loadout release.
#
#   scripts/make-dmg.sh 1.0.0                 # build/release/Loadout.app -> build/release/Loadout-1.0.0.dmg
#   scripts/make-dmg.sh 1.0.0 path/to/Loadout.app path/to/out-dir
#
# The image holds Loadout.app and an Applications shortcut, laid out by scripts/dmg/DS_Store
# (a 540×360 window, no background picture). The mounted volume's icon is the app's
# current AppIcon: the PNGs in Loadout/Assets.xcassets/AppIcon.appiconset are turned into an
# .icns with iconutil, saved as .VolumeIcon.icns at the volume root, and the root gets
# the custom-icon flag (SetFile -a C) so Finder and the desktop show it. Change the app
# icon and the next dmg follows; there's no separate icon file to keep in sync.
#
# It never opens a Finder window: the image is attached with -nobrowse at a private
# mount point and detached again before it's compressed.
set -euo pipefail

VERSION="${1:?usage: scripts/make-dmg.sh <version> [Loadout.app] [out-dir]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${2:-$ROOT/build/release/Loadout.app}"
OUT_DIR="${3:-$(dirname "$APP")}"
VOLNAME="Loadout"
ICONS="$ROOT/Loadout/Assets.xcassets/AppIcon.appiconset"
OUT="$OUT_DIR/Loadout-$VERSION.dmg"

# Refuse to package a version the project doesn't build, or with a stale README.
# (A release also runs `scripts/check-version.sh --release`, see docs/RELEASING.md.)
"$ROOT/scripts/check-version.sh" "$VERSION"

[ -d "$APP" ] || { echo "No app at $APP (build the Release app first, see docs/RELEASING.md)" >&2; exit 1; }
SETFILE="$(command -v SetFile || xcrun --find SetFile 2>/dev/null || true)"
[ -n "$SETFILE" ] || { echo "SetFile not found (install Xcode or its command line tools)" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/loadout-dmg.XXXXXX")"
MNT="$WORK/mnt"
cleanup() {
  if mount | grep -q " on $MNT "; then hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# 1. Volume icon from the AppIcon PNGs (their names already follow the .iconset scheme).
mkdir "$WORK/Loadout.iconset"
for size in 16 32 128 256 512; do
  for name in "icon_${size}x${size}.png" "icon_${size}x${size}@2x.png"; do
    [ -f "$ICONS/$name" ] || { echo "Missing $ICONS/$name" >&2; exit 1; }
    cp "$ICONS/$name" "$WORK/Loadout.iconset/"
  done
done
iconutil -c icns "$WORK/Loadout.iconset" -o "$WORK/VolumeIcon.icns"

# 2. What goes on the image.
mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/Loadout.app"
ln -s /Applications "$WORK/stage/Applications"
cp "$WORK/VolumeIcon.icns" "$WORK/stage/.VolumeIcon.icns"
cp "$ROOT/scripts/dmg/DS_Store" "$WORK/stage/.DS_Store"

# 3. A writable image, so the volume root can get the custom-icon flag.
hdiutil create -quiet -srcfolder "$WORK/stage" -volname "$VOLNAME" -fs HFS+ \
  -format UDRW -ov "$WORK/rw.dmg"
mkdir "$MNT"
hdiutil attach -quiet -nobrowse -noautoopen -noverify -readwrite -mountpoint "$MNT" "$WORK/rw.dmg"
"$SETFILE" -a C "$MNT"
"$SETFILE" -a V "$MNT/.VolumeIcon.icns"   # keep the icon file itself hidden
sync
hdiutil detach "$MNT" -quiet

# 4. Compress.
mkdir -p "$OUT_DIR"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT"
echo "Made $OUT"
