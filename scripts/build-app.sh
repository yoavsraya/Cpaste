#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CONFIG="${1:-release}"
IDENTITY="${CPASTE_SIGN_IDENTITY:-Cpaste Dev}"
APP="build/Cpaste.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Cpaste"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cpaste"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Icons/cpaste-menu-bar.svg "$APP/Contents/Resources/"
codesign --force --sign "$IDENTITY" "$APP"
echo "built $APP signed as $IDENTITY"
