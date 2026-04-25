#!/usr/bin/env bash
# Build SPM executable + wrap as macOS .app bundle.
# Usage: ./scripts/build-bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

echo "==> swift build --configuration $CONFIG"
swift build --configuration "$CONFIG"

BIN_PATH=".build/$CONFIG/LingoPulseApp"
if [ ! -f "$BIN_PATH" ]; then
    echo "ERROR: binary not found at $BIN_PATH" >&2
    exit 1
fi

BUNDLE="LingoPulse.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/LingoPulseApp"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc sign with App Group entitlements so the main app can write to the
# shared UserDefaults suite (group.com.lingopulse.shared) that the IME reads.
codesign --force --deep --sign - \
    --entitlements "$APP_DIR/Resources/LingoPulseApp.entitlements" \
    "$BUNDLE"

echo "==> Bundle: $APP_DIR/$BUNDLE"
echo "Run with: open '$APP_DIR/$BUNDLE'"
echo "Or:       '$APP_DIR/$BUNDLE/Contents/MacOS/LingoPulseApp'"
