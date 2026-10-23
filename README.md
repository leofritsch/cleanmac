# Clean Mac

A small macOS app that shows where your disk went and cleans what's safe to clean, with a focus on Xcode and developer tooling.

Besides Xcode (caches, previews, playgrounds, simulators, duplicate runtimes, DerivedData, archives), it finds the storage that's hard to see in Finder: app caches, leftovers from removed apps, package caches, AI models, project build folders, device backups, snapshots and hidden dot-folders.

## Download

**[Download Clean Mac](https://github.com/leofritsch/cleanmac/releases/latest/download/CleanMac.dmg)** (signed and notarized). Open the DMG and drag Clean Mac into Applications.

Requires macOS 26 or later, on Apple silicon or Intel.

### Full Disk Access

Mail, Messages, Safari, device backups, the Trash and other apps' containers are protected by macOS. To measure them, grant **System Settings › Privacy & Security › Full Disk Access** to Clean Mac. The app shows a banner with a button to that pane, and rescans once access is granted.

## Sections

| Section | What it covers |
| --- | --- |
| Overview | The whole disk as a core sample of layers, largest folders, growth since your last scan, and what's ready to clean |
| Xcode | DerivedData per project (flags projects that no longer exist), simulator runtimes (flags duplicate builds), simulators (flags unavailable ones), device support, previews/playground/test simulators, caches and logs, archives, extra Xcode installs |
| Developer tools | npm, yarn, pnpm, bun, Homebrew, pip, uv, conda, CocoaPods, Gradle, Cargo, Go and more; test browsers; editor caches; AI models (Hugging Face, Ollama, LM Studio); toolchains; Docker/OrbStack disks |
| Project builds | `node_modules`, `.next`, `target`, `.build`, `Pods`, `.venv` and more inside your code folders, with how long each project has been idle |
| App caches & data | `~/Library/Caches`, sandboxed caches, Chromium/Electron caches hidden inside Application Support, data left by apps you removed, and every app's data folder |
| Hidden storage | iPhone backups and firmware, installers, Trash, files over 1 GB, cloud drive downloads, media libraries, Mail/Messages, VMs, logs, APFS snapshots and purgeable space, swap, dot-folders |
| Explore | Browse any folder sorted by size |

## Safety

- Every row is tagged **Rebuilds itself**, **Check before removing**, or **Contains your data**. "Select recommended" only picks items that rebuild themselves or are clearly stale.
- Files go to the Trash by default. You can switch to deleting immediately in the confirmation sheet.
- Simulators, runtimes and preview devices are removed with `xcrun simctl`, Time Machine snapshots with `tmutil`. Clean Mac doesn't delete those files directly.
- A path guard refuses to remove your home folder, top-level Library folders, Documents/Desktop/Downloads, keychains and anything outside your home or `/Applications`.
- Apple's own app containers and media libraries are shown for reference only.

Clean Mac has no network access, analytics or accounts. Everything it measures stays on your Mac.

## History

Each full scan is saved to `~/Library/Application Support/Clean Mac/history.json` (scans within an hour replace each other). The overview compares against the most recent scan that's at least a day old, so you can see which folders grew.

## Build from source

Requires Xcode 26.

```sh
./scripts/build-app.sh
open "build/Clean Mac.app"
```

Local builds are ad-hoc signed, so macOS treats each rebuild as a new app: grant Full Disk Access again after rebuilding. Releases are signed with a Developer ID, so access granted to a release carries over to the next one.

### Development

```sh
swift build                                     # debug build
.build/release/CleanMac --measure ~/some/path   # compare the sizer with du -sk
CLEANMAC_CAPTURE=/tmp/shots "build/Clean Mac.app/Contents/MacOS/CleanMac"   # scan, screenshot every section, quit
```

`scripts/make-icon.swift` draws the app icon as an Icon Composer document (`build/AppIcon.icon`). `build-app.sh` compiles it with `actool`, so macOS renders it in its default, dark, clear and tinted styles.

Releases are built, notarized and published with `scripts/release.sh` and `scripts/publish-release.sh`; see [RELEASE.md](RELEASE.md).

## License

[MIT](LICENSE)
