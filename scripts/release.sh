#!/bin/sh
# Builds a release of a Mac app: Release build → sign everything inside-out (Developer ID, hardened runtime)
# → notarize + staple the app → DMG with an installer window → sign → notarize + staple the DMG → verify.
# Settings live in scripts/release/config.sh, project-specific build and signing in scripts/release/hooks.sh (optional).
# From the macos-release kit (the pipeline that ships ShortCut). See RELEASE.md for the one-time setup.
#
#   scripts/release.sh                          full release (needs the notary profile)
#   NOTARIZE=0 scripts/release.sh               signed, not notarized (local check)
#   IDENTITY=- NOTARIZE=0 scripts/release.sh    ad-hoc dry run: no keychain, no network
set -eu

ROOT=${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
HERE=${HERE:-$ROOT/scripts/release}
OUT=${OUT:-$ROOT/build/release}
. "$HERE/config.sh"
DMG_NAME=${DMG_NAME:-$APP_NAME}
IDENTITY=${IDENTITY:-"Developer ID Application"}
NOTARIZE=${NOTARIZE:-1}
APP="$OUT/$APP_NAME.app"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# Real signatures get a secure timestamp and the hardened runtime (both required for notarization). An ad-hoc
# dry run gets neither: ad-hoc code has no Team ID, so the runtime's library validation would reject its libraries.
if [ "$IDENTITY" = "-" ]; then HARDEN=""; else HARDEN="--timestamp --options runtime"; fi
sign() { codesign --force $HARDEN --sign "$IDENTITY" "$@"; }
[ -f "$HERE/hooks.sh" ] && . "$HERE/hooks.sh"

step "Preflight"
if [ "$IDENTITY" != "-" ]; then
  security find-identity -v -p codesigning | grep -q "$IDENTITY" || fail "No signing identity matching \"$IDENTITY\""
fi
if [ "$NOTARIZE" = 1 ]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "Notary profile \"$NOTARY_PROFILE\" not found. Run the one-time setup in RELEASE.md."
fi

step "Release build"
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$ROOT"
if command -v build_app >/dev/null 2>&1; then
  # The project builds itself (e.g. a SwiftPM app with its own bundling script) and leaves the app, ad hoc, at $APP.
  build_app
  [ -d "$APP" ] || fail "build_app didn't leave $APP"
else
  if [ -f project.yml ]; then
    command -v xcodegen >/dev/null || fail "xcodegen is missing (brew install xcodegen)"
    xcodegen generate >/dev/null
  fi
  if [ -n "${WORKSPACE:-}" ]; then set -- -workspace "$WORKSPACE"; else set -- -project "$PROJECT"; fi
  [ -n "${ARCHS:-}" ] && set -- "$@" "ARCHS=$ARCHS"
  # Built ad hoc; the signing below is ours, so it's the same for every project and needs no Xcode account. Each
  # target keeps the entitlements it declares, without the debugging one Xcode adds to ad-hoc builds.
  xcodebuild "$@" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$OUT/dd" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build -quiet
  ditto "$OUT/dd/Build/Products/Release/$APP_NAME.app" "$APP"
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "$APP_NAME $VERSION ($BUILD)"
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
case "$ENTITLEMENTS" in *get-task-allow*)
  fail "The app's entitlements file asks for get-task-allow (debugging), which notarization rejects. Remove it for Release." ;;
esac
case "$ENTITLEMENTS" in *com.apple.developer.*)
  fail "The app uses entitlements that need a Developer ID provisioning profile (iCloud, push, …). This kit signs without profiles; export with Xcode's Developer ID method instead." ;;
esac
step "Permissions"
sh "$HERE/check-permissions.sh" "$APP" || fail "Fix the permissions above, then release again."
echo "  bundle ID $(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/Info.plist") (macOS remembers what the user granted under this ID and your team)"

step "Sign (inside-out)"
is_macho() { file -b "$1" | grep -qE "Mach-O.*(executable|shared library|bundle)"; }
is_tool() { file -b "$1" | grep -q "Mach-O.*executable"; }
code_bundle() {
  case "$1" in
    *.framework) return 0 ;;
    *.app|*.xpc|*.appex|*.bundle|*.plugin|*.systemextension) ;;
    *) return 1 ;;
  esac
  # Resource-only bundles (e.g. SwiftPM's) aren't code; the app's seal covers them.
  /usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$1/Contents/Info.plist" >/dev/null 2>&1
}
# A standalone tool its maker (or the hook) already signed for distribution keeps that signature.
distributable() {
  [ "$IDENTITY" != "-" ] && codesign --verify --strict "$1" 2>/dev/null || return 1
  INFO=$(codesign -dvv "$1" 2>&1)
  echo "$INFO" | grep -q "^Authority=Developer ID Application" && echo "$INFO" | grep -q "^Timestamp=" \
    && echo "$INFO" | grep -q "flags=.*runtime"
}
# Code that needs its own entitlements is signed by the project's hook first; the pass below keeps it.
if command -v sign_first >/dev/null 2>&1; then sign_first; fi
# Children before parents (find -depth), so every bundle's seal covers code that is already signed.
find "$APP/Contents" -depth -mindepth 1 \( -type d -o -type f \) | while read -r f; do
  if [ -d "$f" ]; then
    code_bundle "$f" || continue
  else
    is_macho "$f" || continue
    if is_tool "$f" && distributable "$f"; then echo "  keeping the Developer ID signature of ${f#"$APP"/}"; continue; fi
  fi
  LOG=$(sign --preserve-metadata=entitlements "$f" 2>&1) || fail "Couldn't sign ${f#"$APP"/}: $LOG"
done
# The app last, so its seal covers everything signed above.
sign --preserve-metadata=entitlements "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

if command -v smoke_test >/dev/null 2>&1; then
  step "Smoke test the signed tools"
  # Signing can break loading (e.g. library validation); the hook runs each tool exactly as the app ships it.
  smoke_test
fi

notarize() { # file-to-submit, thing-to-staple
  step "Notarize $(basename "$2")"
  RESULT=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist)
  STATUS=$(echo "$RESULT" | plutil -extract status raw -)
  ID=$(echo "$RESULT" | plutil -extract id raw -)
  if [ "$STATUS" != "Accepted" ]; then
    xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fail "Notarization $STATUS ($ID)"
  fi
  xcrun stapler staple "$2"
  xcrun stapler validate "$2"
}

if [ "$NOTARIZE" = 1 ]; then
  # Stapling the app itself means it opens offline once it's been dragged out of the DMG.
  ditto -c -k --keepParent "$APP" "$OUT/$APP_NAME-notarize.zip"
  notarize "$OUT/$APP_NAME-notarize.zip" "$APP"
  rm "$OUT/$APP_NAME-notarize.zip"
  spctl --assess --type execute --verbose=2 "$APP"
fi

step "DMG"
swift "$HERE/dmg-background.swift" "$OUT/bg.png" 1 "$DMG_CAPTION" $DMG_ACCENTS
swift "$HERE/dmg-background.swift" "$OUT/bg@2x.png" 2 "$DMG_CAPTION" $DMG_ACCENTS
tiffutil -cathidpicheck "$OUT/bg.png" "$OUT/bg@2x.png" -out "$OUT/background.tiff" >/dev/null
VENV="$ROOT/build/.release-venv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "dmgbuild>=1.6.1,<2"
fi
ICON=$(/usr/libexec/PlistBuddy -c "Print CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true)
ICNS="$APP/Contents/Resources/${ICON%.icns}.icns"
set -- -D app="$APP" -D background="$OUT/background.tiff"
[ -n "$ICON" ] && [ -f "$ICNS" ] && set -- "$@" -D volicon="$ICNS"
DMG="$OUT/$DMG_NAME-$VERSION.dmg"
"$VENV/bin/dmgbuild" -s "$HERE/dmg-settings.py" "$@" "$APP_NAME" "$DMG"
sign "$DMG"
codesign --verify --verbose=1 "$DMG"

if [ "$NOTARIZE" = 1 ]; then
  notarize "$DMG" "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

  step "Verify the DMG as a user gets it"
  M=$(mktemp -d)
  hdiutil attach -nobrowse -readonly -mountpoint "$M" "$DMG" >/dev/null
  INSIDE=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$M/$APP_NAME.app/Contents/Info.plist")
  OK=1
  xcrun stapler validate "$M/$APP_NAME.app" >/dev/null || OK=0
  spctl --assess --type execute "$M/$APP_NAME.app" 2>/dev/null || OK=0
  hdiutil detach "$M" >/dev/null
  [ "$OK" = 1 ] || fail "The app inside the DMG isn't stapled, or Gatekeeper rejects it"
  [ "$INSIDE" = "$VERSION" ] || fail "The DMG holds $APP_NAME $INSIDE, not $VERSION"
  echo "  the app inside is $VERSION, stapled and accepted by Gatekeeper"
fi

step "Done"
echo "$DMG"
shasum -a 256 "$DMG"
