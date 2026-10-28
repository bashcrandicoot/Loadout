# Releasing a new version of Loadout

Loadout checks for updates with [Sparkle](https://sparkle-project.org) 2.10.1, set up like
Lodge. Once a day it reads the update feed, `appcast.xml` in this repo:

    https://raw.githubusercontent.com/bashcrandicoot/Loadout/main/appcast.xml

When the feed lists a newer build, Loadout offers it, downloads the zip from the GitHub
release and installs it. It only installs a zip signed with Loadout's private Sparkle key,
so nobody else can push an update to your users.

> **Beta.** Loadout has no release yet: `appcast.xml` is empty, there are no tags or GitHub
> releases, and the README has no "Current version" line. Don't release until Sebastian says
> it's launch time. Every push (tags included) needs his OK.

## One-time setup (already done)

- Loadout has **its own signing key**, separate from Lodge's. It is in the login Keychain
  under the Keychain account **`loadout`** (Keychain Access → login → search for `sparkle`;
  the item is called *Private key for signing Sparkle updates*, account `loadout`). Lodge's
  key is the one under Sparkle's default account `ed25519`; never use it for Loadout, and
  never run Sparkle's tools for Loadout without `--account loadout`.
- **Back it up**: if you lose it, copies of Loadout already out there can never accept an
  update again. Export it to a file you keep somewhere safe (a password manager or an
  encrypted drive, never this repo):

      <sparkle-bin>/generate_keys --account loadout -x ~/Desktop/loadout-sparkle-private-key.txt

  then move that file somewhere safe. On a new Mac, import it with
  `generate_keys --account loadout -f <file>`.
- The **public key** is `SUPublicEDKey` in `Loadout/Info.plist`
  (`KCsaD0Nx8QWbHtSsAw2uxKYLaxTRRlqCPUz22laTU+g=`). Never change it.
  `generate_keys --account loadout -p` prints the Keychain's copy; they must match.
- **Signing.** Loadout is ad-hoc signed with the Hardened Runtime on and no App Sandbox.
  Sparkle.framework is ad-hoc signed too, and an ad-hoc app has no Team ID, so the Hardened
  Runtime's library validation would refuse to load it. `Loadout/Loadout.entitlements`
  therefore has `com.apple.security.cs.disable-library-validation`. (Lodge turns the
  Hardened Runtime off instead.) Sparkle accepts ad-hoc builds because updates are
  EdDSA-signed. With a Developer ID certificate later, sign Loadout and Sparkle with it,
  drop that entitlement and notarize.

## Every release

Example: releasing **1.0.1**. Before step 1, get the candidate ready:

- **Bump the version.** In Xcode, Loadout project → Loadout target → General:
  *Version* (`MARKETING_VERSION`) `1.0.1`, and *Build* (`CURRENT_PROJECT_VERSION`) one more
  than the last release. **Sparkle compares the build number**, so it must always go up;
  never reuse one. Set the LoadoutTests target to the same Version and Build.
  In the same commit, set the README line under the title to
  `Made by **bashframes**. Current version: **1.0.1**.` (for the first release, this line
  replaces the beta note).
- **Build the Release app** (tests first):

      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
      xcodebuild test -project Loadout.xcodeproj -scheme Loadout -destination 'platform=macOS' \
        -derivedDataPath /tmp/loadout-dd
      rm -rf build/release
      xcodebuild -project Loadout.xcodeproj -scheme Loadout -configuration Release \
        -derivedDataPath /tmp/loadout-dd-release CONFIGURATION_BUILD_DIR="$PWD/build/release" build

- **Make the zip and dmg** in `build/release/`:

      (cd build/release && ditto -c -k --keepParent Loadout.app Loadout-1.0.1.zip)
      scripts/make-dmg.sh 1.0.1

  Optionally write release notes as `build/release/Loadout-1.0.1.md` (Markdown). They
  appear in Loadout's "A new version is available" window.

### 1. Gate QA

Hand the build to **Gate** (the QA bot) for a pass/fail check: the DMG and its SHA-256
(`shasum -a 256 build/release/Loadout-1.0.1.dmg`), the version and build number, and what
changed. Go on only after a **pass**. Any fix means a new build, so start again from the
top and send the new build to Gate.

### 2. Version check

    scripts/check-version.sh --release 1.0.1

It fails if any `MARKETING_VERSION` in the project isn't 1.0.1, if the README doesn't say
`Current version: **1.0.1**`, or if it names any other version. (`make-dmg.sh` runs the same
check without `--release`; `make-appcast.sh` runs it with `--release`.)

### 3. Appcast commit

    scripts/make-appcast.sh 1.0.1
    git add appcast.xml && git commit -m "Appcast: Loadout 1.0.1"

`make-appcast.sh` checks the zip (version, `SUPublicEDKey`, a build number higher than any in
the feed, and that the Keychain key for account `loadout` matches the app), signs it with
`generate_appcast --account loadout` and adds a 1.0.1 entry to `appcast.xml` pointing at
`https://github.com/bashcrandicoot/Loadout/releases/download/v1.0.1/Loadout-1.0.1.zip`.
It refuses to write an unsigned entry. The first time, macOS may ask whether
`generate_appcast` can use your Keychain: type your Mac login password and click
**Always Allow**. Nothing is uploaded or pushed.

### 4. Tag

    git tag -a v1.0.1 -m "Loadout 1.0.1"
    git push origin v1.0.1

The tag must be exactly `v1.0.1` (the feed's download link depends on it). Push **only the
tag** here, not `main`: step 5's `--verify-tag` needs the tag on GitHub, and `main` (with
the new appcast) must go last.

### 5. GitHub release

    gh release create v1.0.1 build/release/Loadout-1.0.1.zip build/release/Loadout-1.0.1.dmg \
      --verify-tag --title "Loadout 1.0.1" --notes-file build/release/Loadout-1.0.1.md

`--verify-tag` stops if the tag isn't on GitHub, so `gh` never makes a tag of its own.

### 6. Push

    git push origin main

Do this last: as soon as `appcast.xml` is on `main`, everyone's Loadout sees the update, so
the zip must already be on the release.

### 7. Check it

Open an older Sparkle-enabled Loadout and choose **Loadout ▸ Check for Updates…**.

## Where are Sparkle's tools?

`generate_keys`, `generate_appcast` and `sign_update` come with the Sparkle Swift package:
after any build they're in `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`
(for example `/tmp/loadout-dd/SourcePackages/artifacts/sparkle/Sparkle/bin/`).
`scripts/make-appcast.sh` finds them itself, or set `SPARKLE_BIN` to that folder.
