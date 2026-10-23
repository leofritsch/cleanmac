#!/bin/sh
# Publishes a built, notarized DMG as a GitHub release on the public downloads repo. The asset always has the same
# name, so https://github.com/$RELEASES_REPO/releases/latest/download/$DMG_NAME.dmg points at the newest release.
# Run after scripts/release.sh. From the macos-release kit; see RELEASE.md → Publishing.
#
#   scripts/publish-release.sh             publishes the DMG in build/release
#   scripts/publish-release.sh 1.2.0       publishes that version's DMG
#   DRY_RUN=1 scripts/publish-release.sh   runs every check and prints the notes, uploads nothing
set -eu

ROOT=${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
HERE=${HERE:-$ROOT/scripts/release}
OUT=${OUT:-$ROOT/build/release}
. "$HERE/config.sh"
DMG_NAME=${DMG_NAME:-$APP_NAME}
REPO=${REPO:-$RELEASES_REPO}

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

if [ $# -gt 0 ]; then
  VERSION=$1
else
  # release.sh empties build/release each run, so the one DMG there is the one just built.
  DMG=$(ls "$OUT/$DMG_NAME"-*.dmg 2>/dev/null | head -1) || true
  [ -n "$DMG" ] || fail "No DMG in $OUT. Run scripts/release.sh first."
  VERSION=$(basename "$DMG" .dmg); VERSION=${VERSION#"$DMG_NAME"-}
fi
DMG="$OUT/$DMG_NAME-$VERSION.dmg"
TAG="v$VERSION"
LATEST="https://github.com/$REPO/releases/latest/download/$DMG_NAME.dmg"

step "Checks"
command -v gh >/dev/null || fail "gh is missing (brew install gh)"
gh auth status >/dev/null 2>&1 || fail "gh isn't logged in (gh auth login)"
gh repo view "$REPO" >/dev/null 2>&1 || fail "Can't see $REPO. Create the public downloads repo first (RELEASE.md)."
[ -f "$DMG" ] || fail "No DMG at $DMG. Run scripts/release.sh first."
xcrun stapler validate "$DMG" >/dev/null || fail "$DMG isn't stapled. Only notarized builds are published."
spctl --assess --type open --context context:primary-signature "$DMG" 2>/dev/null || fail "Gatekeeper rejects $DMG"
M=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$M" "$DMG" >/dev/null
INSIDE=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$M/$APP_NAME.app/Contents/Info.plist")
hdiutil detach "$M" >/dev/null
[ "$INSIDE" = "$VERSION" ] || fail "The DMG holds $APP_NAME $INSIDE, not $VERSION"
git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "No tag $TAG in this repo (tag the release commit first)"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then fail "$REPO already has $TAG. Versions are never re-published."; fi
# Open source: the release lives on the source repo itself, on the tag pushed with the release commit (never a new
# one GitHub would make at the branch tip). A separate downloads repo just gets the tag on its own README commit.
SOURCE=$(cd "$ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || SOURCE=""
set --
if [ "$REPO" = "$SOURCE" ]; then
  [ "$(gh repo view "$REPO" --json visibility --jq .visibility)" = "PUBLIC" ] || fail "$REPO is private, so nobody could download from it. Use a public downloads repo."
  git -C "$ROOT" ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null || fail "Push the commit and the tag first (git push && git push --tags)"
  set -- --verify-tag
fi

# The changelog line for this version, without its date and version prefix.
CHANGES=$(grep -m1 "— v$VERSION:" "$ROOT/$CHANGELOG" 2>/dev/null | sed 's/^- [0-9-]* — v[^:]*: *//' \
  | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }') || true
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
NOTES=$(printf '%s\n\n%s Signed and notarized.\n\nSHA-256 of %s.dmg: `%s`\n' \
  "${CHANGES:-$APP_NAME $VERSION.}" "$REQUIREMENTS" "$DMG_NAME" "$SHA")

if [ "${DRY_RUN:-0}" = 1 ]; then
  step "Dry run: would publish $TAG to $REPO as \"$APP_NAME $VERSION\"${1:+ (on the pushed tag)}"
  printf '%s\n' "$NOTES"
  exit 0
fi

step "Publish $TAG to $REPO"
STAGE=$(mktemp -d)
cp "$DMG" "$STAGE/$DMG_NAME.dmg"
gh release create "$TAG" "$STAGE/$DMG_NAME.dmg" --repo "$REPO" --title "$APP_NAME $VERSION" --notes "$NOTES" --latest "$@"
rm -rf "$STAGE"

step "Verify"
# GitHub may take a moment to point "latest" at the new release.
for i in 1 2 3 4 5 6; do
  GOT=$(curl -fsSL "$LATEST" | shasum -a 256 | cut -d' ' -f1) || GOT=""
  [ "$GOT" = "$SHA" ] && break
  sleep 5
done
[ "$GOT" = "$SHA" ] || fail "$LATEST doesn't serve the new DMG yet"
echo "$LATEST serves $APP_NAME $VERSION ($SHA)"
gh release view "$TAG" --repo "$REPO" --json url --jq .url
