# Loadout

**Loadout for DaVinci Resolve** puts LUTs, DCTLs and Fusion templates where DaVinci Resolve looks for them. Drop a file, a folder, a creator's pack or a `.zip` on the window, check what Loadout found, and click **Install to Resolve**.

Made by **bashframes**. Current version: **1.0.0**.

## What it does

- **Installs by drag and drop.** Files, folders, packs and zips (zips inside zips too). `.drfx` bundles stay zipped, as Resolve expects. Readmes, previews, `__MACOSX` and `.DS_Store` files are skipped.
- **Knows what each file is.** `.cube`, `.3dl`, `.ilut`, `.olut` and `.mga` LUTs; `.dctl` and `.dctle` DCTLs; Fusion `.setting` templates (titles, transitions, effects and generators, from their folders or contents); `.drfx` bundles. A `.cube` with no LUT data or a `look.cube.txt` is refused with a reason. When it can't tell what a loose `.setting` is, it asks once per pack.
- **Puts each file in the right place.**
  - LUTs and DCTLs: `/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT/Loadout/<Pack>/`
  - Templates: `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Templates/Edit/<Titles|Transitions|Effects|Generators>/<Pack>/`
  - `.drfx` bundles: the `Fusion/Templates` folder.
- **Keeps a Library** of everything in those folders, grouped by pack and filterable by type, with search, sort, a before/after LUT preview on built-in sample frames, **Reveal in Finder**, **Turn Off / Turn On** and **Move to Trash**. Turning an item off moves it to `~/Library/Application Support/Loadout/Parked/` (same relative path) so Resolve stops loading it; turning it on puts it back.
- **Handles updates.** If a file is already there: Replace (the old one goes to the Trash), Keep Both, or Skip.
- **Says what Resolve needs.** New LUTs show after **Update Lists** (Project Settings ▸ Color Management) or a restart; new templates and DCTLs after a restart.
- Never deletes anything: removed and replaced files go to the Trash. Resolve's own LUTs (ACES, Arri, Film Looks…) are hidden by default and never changed.

If macOS protects Resolve's LUT folder, Loadout asks for an administrator password with the standard macOS prompt. It never sees or stores the password.

Loadout doesn't use Resolve's scripting API (that's Studio only), so it works with the free version of DaVinci Resolve too. The Mac App Store version of Resolve isn't supported yet.

## Requirements

- macOS 14 Sonoma or later
- DaVinci Resolve (free or Studio, direct download from Blackmagic Design)

## Build

Open `Loadout.xcodeproj` in Xcode and press ⌘R, or from Terminal:

```sh
# Tests (they use temporary folders, never Resolve's real ones)
xcodebuild test -project Loadout.xcodeproj -scheme Loadout -destination 'platform=macOS'

# Release app -> build/release/Loadout.app (ad-hoc signed, hardened runtime)
xcodebuild -project Loadout.xcodeproj -scheme Loadout -configuration Release \
  -derivedDataPath build/dd CONFIGURATION_BUILD_DIR="$PWD/build/release" build

# Disk image -> build/release/Loadout-<version>.dmg
scripts/make-dmg.sh 1.0.0
```

### Trying it safely

`LOADOUT_SANDBOX=/some/folder` makes Loadout use stand-in Resolve folders under that folder instead of the real ones:

```sh
open -n --env LOADOUT_SANDBOX="$HOME/Desktop/LoadoutSandbox" build/release/Loadout.app
```

## Not affiliated

DaVinci Resolve is a trademark of Blackmagic Design. Loadout is an independent app and isn't made or endorsed by Blackmagic Design.

## License

MIT. See [LICENSE](LICENSE).
