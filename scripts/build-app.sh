#!/bin/bash
# Builds "build/Clean Mac.app" (release, ad-hoc signed). scripts/release.sh signs and notarizes it for distribution.
#   scripts/build-app.sh                          this Mac's architecture, for local use
#   ARCHS="arm64 x86_64" scripts/build-app.sh     universal, as releases ship
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=0.3.0   # what users see
BUILD=1         # goes up by 1 with every release and is never reused

ARCH_FLAGS=()
for arch in ${ARCHS:-$(uname -m)}; do ARCH_FLAGS+=(--arch "$arch"); done
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/CleanMac"

APP="build/Clean Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CleanMac"

ICON=build/AppIcon.icon
if [ ! -f "$ICON/icon.json" ] || [ scripts/make-icon.swift -nt "$ICON/icon.json" ]; then
  rm -rf "$ICON"
  swift scripts/make-icon.swift "$ICON"
fi
# Assets.car carries the layered icon macOS renders in default, dark, clear and tinted; AppIcon.icns is the flat fallback
xcrun actool "$PWD/$ICON" --compile "$PWD/$APP/Contents/Resources" --app-icon AppIcon \
  --platform macosx --target-device mac --minimum-deployment-target 26.0 \
  --output-partial-info-plist "$PWD/build/AppIcon-partial.plist" >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clean Mac</string>
  <key>CFBundleDisplayName</key><string>Clean Mac</string>
  <key>CFBundleIdentifier</key><string>com.leofritsch.CleanMac</string>
  <key>CFBundleExecutable</key><string>CleanMac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Léo Fritsch. MIT License.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($VERSION, build $BUILD)"
