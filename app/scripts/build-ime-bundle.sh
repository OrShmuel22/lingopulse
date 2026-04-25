#!/usr/bin/env bash
# Build the LingoPulseIME SPM executable and wrap it as a macOS .app bundle.
# The resulting bundle can be installed to ~/Library/Input Methods/ for testing.
# Usage: ./scripts/build-ime-bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

echo "==> swift build --product LingoPulseIME --configuration $CONFIG"
swift build --product LingoPulseIME --configuration "$CONFIG"

BIN_PATH=".build/$CONFIG/LingoPulseIME"
if [ ! -f "$BIN_PATH" ]; then
    echo "ERROR: binary not found at $BIN_PATH" >&2
    exit 1
fi

BUNDLE="LingoPulseIME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/LingoPulseIME"
cp Resources/IMEInfo.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc sign. A real distribution build would use a Developer ID.
codesign --force --deep --sign - "$BUNDLE"

echo "==> Bundle: $APP_DIR/$BUNDLE"
echo "Install:   cp -R '$APP_DIR/$BUNDLE' ~/Library/Input\ Methods/"
echo "Activate:  Open System Settings > Keyboard > Input Sources and add LingoPulse."
