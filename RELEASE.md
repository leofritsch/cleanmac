# Releasing Clean Mac

One command builds a release that opens on any Mac without warnings:

```sh
scripts/release.sh
```

It ends with `build/release/CleanMac-<version>.dmg` and its SHA-256. Then `scripts/publish-release.sh` publishes that DMG as a GitHub release. Settings are in `scripts/release/config.sh`. The scripts come from the `macos-release` kit; to upgrade them, copy the kit's `release.sh` and `publish-release.sh` over these.

## Repository

[leofritsch/cleanmac](https://github.com/leofritsch/cleanmac) is public and holds both the source and the releases. Each release is published on the tag pushed with its release commit.

**Download link for websites:** <https://github.com/leofritsch/cleanmac/releases/latest/download/CleanMac.dmg>. It always serves the newest release, because every release names its asset `CleanMac.dmg`. Drafts and pre-releases never count as "latest".

## What it does

1. **Release build,** ad hoc, universal (Apple silicon and Intel). Clean Mac is a SwiftPM package with no Xcode project, so the `build_app` hook in `scripts/release/hooks.sh` runs `scripts/build-app.sh`, which also compiles the icon and writes Info.plist.
2. **Checks permissions** (`scripts/release/check-permissions.sh`): every protected resource the app asks for has both its entitlement and its usage string. Clean Mac asks for none. Its one permission, Full Disk Access, is granted in System Settings: the app shows a banner with a button to that pane and rescans once access is granted.
3. **Signs inside-out** with the Developer ID Application certificate, the hardened runtime and a secure timestamp. Clean Mac bundles no outside tools, so this is just the app.
4. **Notarizes and staples the app,** so it also opens offline once it's been copied out of the DMG.
5. **Builds the DMG** with `dmgbuild`: a 640×440 installer window with the app, an Applications link, and a background drawn by `scripts/release/dmg-background.swift`.
6. **Signs, notarizes and staples the DMG,** then mounts it and checks that the app inside is the new version, stapled and accepted by Gatekeeper.

## One-time setup

1. **Certificate:** "Developer ID Application" for team HTJR8J8T9K must be in the login keychain (`security find-identity -v -p codesigning`).
2. **Notary credentials:** make an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords. Then store it under the profile name in `config.sh`:

   ```sh
   xcrun notarytool store-credentials ShortCut --apple-id <your Apple ID email> --team-id HTJR8J8T9K
   ```

   One profile works for every app on the team; this one was first made for ShortCut.
3. **Tools:** Xcode 26, and `gh` (logged in) for publishing. The script installs `dmgbuild` itself, into `build/.release-venv`.

## Each release

1. In `scripts/build-app.sh`, set `VERSION`, and raise `BUILD` by 1. Add the changelog line `- YYYY-MM-DD — v<version>: …` to `CHANGELOG.md`.
2. Commit and tag (`v<version>`), then run `scripts/release.sh`. The two notarizations take a few minutes each.
3. Push the commit and tag, then publish: `scripts/publish-release.sh` (`DRY_RUN=1` first to see the notes).
4. Check it as a stranger would get it: mark the DMG as downloaded with `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" build/release/CleanMac-<version>.dmg`, and reset permissions with `tccutil reset All com.leofritsch.CleanMac`. Then open it, drag the app to Applications and launch it. There should be only the normal "downloaded from the internet" prompt; Full Disk Access is asked for by the app's banner.

## Variants

| Command | Use |
|---|---|
| `NOTARIZE=0 scripts/release.sh` | Signed, not notarized: checks signing locally, no upload |
| `IDENTITY=- NOTARIZE=0 scripts/release.sh` | Ad-hoc dry run: no keychain, no network |
| `DRY_RUN=1 scripts/publish-release.sh` | Every publishing check, plus the notes, without uploading |

## Sharing the DMG

Any transfer that doesn't change the file's bytes (a download, Telegram, AirDrop, email) keeps the signature and the stapled ticket, offline too. Don't re-zip it; if you must, use `ditto -c -k --keepParent` or Finder's Compress. Recipients can compare `shasum -a 256` with the release notes.

## Publishing rules

A published version is never replaced; ship a new one. To pull a bad release: `gh release delete v<version> --repo leofritsch/cleanmac`. The latest link then falls back to the previous release. Leave out `--cleanup-tag`: the tag belongs to the source.
