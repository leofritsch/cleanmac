# Release settings, read by scripts/release.sh and scripts/publish-release.sh (macos-release kit).
APP_NAME="Clean Mac"                  # the built .app's name, and the DMG's volume name
DMG_NAME="CleanMac"                   # the DMG file and release asset; no space, so the download link stays clean
ARCHS="arm64 x86_64"                  # universal; hooks.sh hands this to scripts/build-app.sh
NOTARY_PROFILE="ShortCut"             # keychain profile from xcrun notarytool store-credentials; one serves the whole team
RELEASES_REPO="leofritsch/cleanmac"   # open source: the releases live on the source repo itself
CHANGELOG="CHANGELOG.md"              # its line "- YYYY-MM-DD — v1.2.0: …" becomes the release notes
REQUIREMENTS="Requires macOS 26 or later, on Apple silicon or Intel."
DMG_CAPTION="Drag Clean Mac into Applications"
DMG_ACCENTS="4F74FF FF7A59"           # the icon's prism: blue glow, blue-to-coral arrow
# No SCHEME or PROJECT: Clean Mac is a SwiftPM package, built by build_app in hooks.sh.
