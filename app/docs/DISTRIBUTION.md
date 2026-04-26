# Distribution

## Current state — ad-hoc signed DMG

`./scripts/build-dmg.sh [debug|release]` produces `LingoPulse-X.Y.Z.dmg` with:

- `LingoPulse.app` (embeds `LingoPulseIME.app` in Contents/Resources/)
- `/Applications` symlink for drag-to-install
- `Read Me.txt`

The DMG is ad-hoc signed (`codesign --sign -`). On first open, Gatekeeper shows
"Apple cannot check it for malicious software." Users must right-click → Open to
bypass this. Acceptable for personal/dogfood use; not for public distribution.

## What you need for clean distribution

**Apple Developer ID** ($99/yr via developer.apple.com) unlocks:

1. Developer ID Application certificate — sign the `.app`
2. Developer ID Installer certificate — sign the `.dmg` (optional but recommended)
3. Notarization — Apple scans the binary; staple the ticket so Gatekeeper passes offline

## Notarization steps (when ready)

```bash
# 1. Build with Developer ID cert instead of '-'
codesign --force --deep --sign "Developer ID Application: Your Name (TEAMID)" \
    --entitlements app/Resources/LingoPulseApp.entitlements \
    app/LingoPulse.app

# 2. Rebuild DMG with signed app, then sign the DMG
./scripts/build-dmg.sh release   # modify script to use Developer ID cert first

# 3. Submit for notarization
xcrun notarytool submit LingoPulse-x.y.z.dmg \
    --apple-id you@example.com \
    --team-id ABCDE12345 \
    --password "@keychain:notarytool" \
    --wait

# 4. Staple the notarization ticket into the DMG
xcrun stapler staple LingoPulse-x.y.z.dmg
```

After stapling, Gatekeeper passes silently — no right-click needed.

## Checklist before public release

- [ ] Enroll in Apple Developer Program
- [ ] Generate Developer ID Application + (optionally) Installer certs in Keychain
- [ ] Replace `--sign -` in build-bundle.sh and build-dmg.sh with the cert name
- [ ] Notarize + staple
- [ ] Test on a clean machine (different Apple ID, no prior trust)
