#!/usr/bin/env bash
# Build a drag-to-Applications DMG from the bundled LingoPulse.app
# Usage: ./scripts/build-dmg.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

# Build the app bundle first (which embeds the IME bundle inside)
echo "==> Building app bundle ($CONFIG)..."
./scripts/build-bundle.sh "$CONFIG"

APP_BUNDLE="LingoPulse.app"
[ -d "$APP_BUNDLE" ] || { echo "ERROR: $APP_BUNDLE not found after build" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
DMG_NAME="LingoPulse-${VERSION}"

# Staging directory: holds bundle + symlink to /Applications + optional README
STAGING="$(mktemp -d)"
trap "rm -rf '$STAGING'" EXIT

cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Optional: drop a README.txt at the root
cat > "$STAGING/Read Me.txt" <<EOF
LingoPulse — local English refinement tool

To install: drag LingoPulse to the Applications folder.
First launch: macOS will prompt for Accessibility and Input Method permissions.

For source + docs: see https://github.com/your-org/lingopulse
EOF

# Create the DMG
OUTPUT="$APP_DIR/${DMG_NAME}.dmg"
rm -f "$OUTPUT"

# Step 1: create writable DMG from staging
TEMP_DMG="$(mktemp -t LingoPulseDMG.XXXXXX).dmg"
trap "rm -rf '$STAGING' '$TEMP_DMG'" EXIT

hdiutil create \
    -volname "LingoPulse" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDRW \
    -size 100m \
    "$TEMP_DMG"

# Step 2: convert to compressed read-only DMG
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"
rm -f "$TEMP_DMG"

# Step 3: ad-hoc sign the DMG (required so Gatekeeper doesn't immediately reject;
# real distribution would notarize here)
codesign --force --sign - "$OUTPUT"

echo
echo "==> DMG: $OUTPUT"
echo
echo "Distribute by sharing this file. Recipients double-click → drag LingoPulse to Applications."
echo "First open: right-click → Open (ad-hoc signed; without Apple Developer ID, Gatekeeper warns)."
echo "Notarized DMG required for clean sharing — see docs/DISTRIBUTION.md when ready."
