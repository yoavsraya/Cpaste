#!/bin/bash
# Builds build/Cpaste.app from the Swift package, with Sparkle embedded, and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CONFIG="${1:-release}"
IDENTITY="${CPASTE_SIGN_IDENTITY:-Cpaste Dev}"
APP="${CPASTE_APP:-build/Cpaste.app}"
# Sparkle compares builds by this number, so it must rise with every release. The commit count does.
BUILD="${CPASTE_BUILD:-$(git rev-list --count HEAD)}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Cpaste"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Cpaste"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Icons/cpaste-menu-bar.svg "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
if [ -n "${CPASTE_FEED_URL:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $CPASTE_FEED_URL" "$APP/Contents/Info.plist"
fi

# SwiftPM links against Sparkle but does not copy the framework into a hand-made bundle.
SPARKLE="$(find .build/artifacts -type d -name Sparkle.framework -path '*macos*' | head -n1)"
[ -n "$SPARKLE" ] || { echo "Sparkle.framework not found under .build/artifacts" >&2; exit 1; }
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE" "$FRAMEWORK"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Cpaste"

# Inside out, so each signature covers code that is already signed.
codesign --force --sign "$IDENTITY" "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" "$FRAMEWORK/Versions/B/Autoupdate"
codesign --force --sign "$IDENTITY" "$FRAMEWORK/Versions/B/Updater.app"
codesign --force --sign "$IDENTITY" "$FRAMEWORK"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP build $BUILD signed as $IDENTITY"
