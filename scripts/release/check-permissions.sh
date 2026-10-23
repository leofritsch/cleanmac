#!/bin/sh
# Checks that every protected resource the app asks for still works in the released (hardened runtime) build:
# each needs its entitlement AND its usage string in Info.plist. Without the entitlement, macOS denies access
# without ever showing the prompt; without the string, macOS kills the app the moment it asks. Debug builds
# usually run without the hardened runtime, so a missing entitlement only shows up after release.
#
#   scripts/release/check-permissions.sh <path/to/App.app>      (release.sh runs it on every build)
set -eu

APP=$1
PLIST="$APP/Contents/Info.plist"
ENT=$(mktemp)
trap 'rm -f "$ENT"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENT" 2>/dev/null || true

# entitlement | what the user sees | usage-string keys (any one of them)
MAP="com.apple.security.device.camera|camera|NSCameraUsageDescription
com.apple.security.device.audio-input|microphone|NSMicrophoneUsageDescription
com.apple.security.personal-information.location|location|NSLocationUsageDescription NSLocationWhenInUseUsageDescription NSLocationAlwaysAndWhenInUseUsageDescription
com.apple.security.personal-information.addressbook|contacts|NSContactsUsageDescription
com.apple.security.personal-information.calendars|calendars and reminders|NSCalendarsUsageDescription NSCalendarsFullAccessUsageDescription NSCalendarsWriteOnlyAccessUsageDescription NSRemindersUsageDescription NSRemindersFullAccessUsageDescription
com.apple.security.personal-information.photos-library|photos|NSPhotoLibraryUsageDescription NSPhotoLibraryAddUsageDescription
com.apple.security.automation.apple-events|controlling other apps (Apple Events)|NSAppleEventsUsageDescription"

has_ent() { [ -s "$ENT" ] && [ "$(/usr/libexec/PlistBuddy -c "Print :$1" "$ENT" 2>/dev/null)" = "true" ]; }
usage() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

ERRORS=""; FOUND=""
NL='
'
while IFS='|' read -r ent label keys; do
  TEXT=""; KEY=""
  for k in $keys; do
    T=$(usage "$k")
    if [ -n "$T" ]; then TEXT=$T; KEY=$k; break; fi
  done
  if [ -n "$TEXT" ] && ! has_ent "$ent"; then
    ERRORS="$ERRORS$NL  $label: Info.plist has $KEY, but the entitlements lack $ent, so the released app is denied without a prompt. Add it to the app's entitlements file."
  elif [ -z "$TEXT" ] && has_ent "$ent"; then
    ERRORS="$ERRORS$NL  $label: the entitlements have $ent, but Info.plist has no usage string (${keys%% *}), so macOS kills the app when it asks. Add one that says why the app needs it."
  elif [ -n "$TEXT" ]; then
    FOUND="$FOUND$NL  $label: \"$TEXT\""
  fi
done <<EOF
$MAP
EOF

if [ -n "$ERRORS" ]; then
  printf '\033[31m✗ Permissions that would break in the released app:%s\033[0m\n' "$ERRORS" >&2
  exit 1
fi
if [ -n "$FOUND" ]; then echo "  asks for:$FOUND"; else echo "  asks for no protected resources (camera, microphone, location, contacts, calendars, photos, Apple Events)"; fi
