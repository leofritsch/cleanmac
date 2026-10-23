# Hooks for scripts/release.sh. Clean Mac is a SwiftPM package with no Xcode project, so it builds with its own
# script; it bundles no outside tools, so there is nothing to sign first or smoke test.

build_app() {
  ARCHS="$ARCHS" "$ROOT/scripts/build-app.sh"
  ditto "$ROOT/build/Clean Mac.app" "$APP"
}
