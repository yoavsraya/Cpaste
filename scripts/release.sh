#!/bin/bash
# Publishes a release and adds it to the update feed, so installed copies offer the update.
# Usage: scripts/release.sh 0.1.6 notes.md
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="${1:?usage: scripts/release.sh <version> <notes.md>}"
NOTES="${2:?usage: scripts/release.sh <version> <notes.md>}"
TAG="v$VERSION"
REPO_URL="https://github.com/yoavsraya/Cpaste"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

[ -f "$NOTES" ] || { echo "no notes file at $NOTES" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or discard your changes first" >&2; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "release from main" >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "$TAG already exists" >&2; exit 1; }

swift test
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
git commit -qam "chore: release $VERSION"
./scripts/package.sh

# generate_appcast signs the zip with the key in the login keychain and merges it into the existing feed.
FEED="$(mktemp -d)"
cp dist/Cpaste.zip "$FEED/Cpaste.zip"
cp "$NOTES" "$FEED/Cpaste.md"
[ ! -f appcast.xml ] || cp appcast.xml "$FEED/appcast.xml"
"$SPARKLE_BIN/generate_appcast" --account cpaste --embed-release-notes \
  --download-url-prefix "$REPO_URL/releases/download/$TAG/" --link "$REPO_URL/releases" "$FEED"
cp "$FEED/appcast.xml" appcast.xml

# Homebrew downloads the same zip and refuses it when the checksum in the cask differs.
SHA="$(shasum -a 256 dist/Cpaste.zip | cut -d' ' -f1)"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/cpaste.rb
git add appcast.xml Casks/cpaste.rb
git commit -qm "chore: add $VERSION to the update feed and the Homebrew cask"

# The download must exist before the feed that points at it goes live.
git tag "$TAG"
git push -q origin "$TAG"
gh release create "$TAG" dist/Cpaste.zip --title "Cpaste $VERSION" --notes-file "$NOTES"
git push -q origin main
echo "released $VERSION: $REPO_URL/releases/tag/$TAG"
