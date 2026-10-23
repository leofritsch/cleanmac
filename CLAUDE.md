# Clean Mac

SwiftUI macOS 26 app, SwiftPM only (no Xcode project).

- Build: `scripts/build-app.sh` → `build/Clean Mac.app` (ad hoc; macOS treats each rebuild as a new app, so Full Disk Access must be granted again).
- Check the UI: `CLEANMAC_CAPTURE=<dir> CLEANMAC_APPEARANCE=dark|light "build/Clean Mac.app/Contents/MacOS/CleanMac"` scans, screenshots every section and quits.
- Check the sizer: `.build/release/CleanMac --measure <path>` against `du -sk`.
- Icon: `scripts/make-icon.swift` writes an Icon Composer document; preview its appearances with Icon Composer's `ictool`.
- Anything that removes files goes through `Cleaner` and `PathGuard` (Core/Cleaner.swift). Tag new items honestly: only things that rebuild themselves may be recommended.
- Release: use the macos-release skill; see RELEASE.md.
