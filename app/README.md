# LingoPulse macOS App — v1

Native menu-bar app that works alongside the LingoPulse IME to suggest grammar / style fixes via the local daemon at `http://127.0.0.1:17823`.

## Architecture

LingoPulse uses an **IME-first** design:

- **LingoPulseIME** — the primary live-correction path. Intercepts keystrokes via InputMethodKit, debounces, calls the daemon, and shows a floating suggestion panel near the caret. Works in all standard Cocoa text fields without requiring Accessibility writes.
- **LingoPulse.app** — menu-bar host. Manages the daemon connection, settings, personal dictionary, and the manual ⌘⌥G refine hotkey.

The AXLiveObserver path (polling focused-element value changes via the Accessibility API) has been removed. The IME supersedes it for live mode.

## Build

Requires Swift 5.9+ (Xcode CLT or full Xcode), macOS 14+.

```bash
cd app
swift build                             # compile only
./scripts/build-bundle.sh debug         # builds + bundles + ad-hoc signs → LingoPulse.app
./scripts/build-ime-bundle.sh debug     # builds + bundles → LingoPulseIME.app
open LingoPulse.app
```

Ad-hoc signing lets Accessibility permission persist across rebuilds without re-prompting.

## First-run permissions

### Accessibility (required for ⌘⌥G manual refine)

1. Launch `LingoPulse.app`
2. macOS prompts "LingoPulse wants to control this computer"
3. System Settings → Privacy & Security → Accessibility → toggle LingoPulse ON
4. Quit and relaunch

### IME registration

The LingoPulseIME bundle is installed to `~/Library/Input Methods/`. macOS only scans this directory **at login**, so the first install requires a logout/login cycle. This matches how Squirrel/RIME, Fcitx5-mac, and other ad-hoc-signed open-source IMEs ship.

1. Run `./scripts/build-ime-bundle.sh debug` and copy the produced `LingoPulseIME.app` to `~/Library/Input Methods/` (the onboarding wizard does this automatically)
2. **Log out and log back in** — required only on first install (or after rebuild changes the bundle's cdhash)
3. After login: System Settings → Keyboard → Input Sources → `+` → English → **LingoPulse** → Add
4. Switch to LingoPulse via the input-source picker in the menu bar (top-right globe icon, or ⌃⇧Space)

If LingoPulse doesn't appear in the `+` list, the cause is almost always that `imklaunchagent` hasn't re-scanned. Logout/login is the fix; force-killing `imklaunchagent` from `sudo` works too. Once added the first time, subsequent app updates don't need another logout — just rebuild + replace the bundle.

A future Apple Developer ID + notarization run would let `TISRegisterInputSource` register the bundle without logout. Documented in `docs/DISTRIBUTION.md`.

### Notifications (optional)

macOS will ask once for notification permission. Grant it to receive cold-start and daemon-down alerts.

## Features

1. **Live IME suggestions** — LingoPulseIME intercepts keystrokes and shows a floating suggestion panel after you pause typing (debounce 1.5s default). Tab to accept, Esc to dismiss, ↑/↓ to cycle edits.
2. **Manual refine** — press ⌘⌥G (or menu bar → Refine Selection) to refine selected text on demand. Falls back to clipboard paste in AX-write-blocked apps (Electron, some browsers).
3. **Personal dictionary** — words/phrases you add are never flagged. Per-app or global scope.
4. **Import / Export** — back up and restore your personal dictionary as JSON.
5. **Settings** — configure daemon URL, debounce, auto-dismiss, hotkey, excluded apps, log level.
6. **Never-fix context menu** — right-click any strikethrough word in the chip to permanently ignore it.

## Hotkeys

| Hotkey | Action |
|--------|--------|
| ⌘⌥G | Manual refine — reads selected text via AX, sends to daemon, writes back (configurable in Settings → Hotkey) |
| ⌘D | Open Personal Dictionary |
| ⌘, | Open Settings |

## IME suggestion panel controls

| Key | Action |
|-----|--------|
| Tab | Accept currently highlighted edit |
| Esc | Dismiss panel |
| ↓ / ↑ | Cycle through edits |

## Manual refine (⌘⌥G) — AX fallback

⌘⌥G reads the current selection via the Accessibility API and writes the refined text back. In apps that block AX writes (some Electron apps, Firefox), the refined text is placed on the clipboard instead — paste with ⌘V.

## IME compatibility testing

Before reporting a bug against a specific app, check `docs/IME-COMPAT.md` for known behavior. To run a manual compatibility pass yourself, follow the step-by-step guide in `docs/IME-DOGFOOD.md`.

## Troubleshooting

**IME suggestions not appearing**
- Confirm LingoPulseIME is selected as your input source in the menu bar.
- Some terminal emulators bypass IMK entirely — use ⌘⌥G for those.

**No chip appears on ⌘⌥G / "AX denied"**
- Check System Settings → Privacy → Accessibility — LingoPulse must be toggled ON.
- Some apps (Electron, some browsers) block AX writes; ⌘⌥G falls back to clipboard paste.

**"Daemon unreachable" notification**
- Ensure the daemon is running: `launchctl list | grep lingopulse`
- Start it manually: `cd lingopulse && python daemon.py` or via the launchd plist.
- Default URL is `http://127.0.0.1:17823` — change in Settings → General if needed.

**Hotkey not working**
- Another app may have registered the same combination. Change it in Settings → Hotkey.
- Quit and relaunch after changing the hotkey.

**View logs**

```bash
# Main app
log stream --predicate 'subsystem == "com.lingopulse.app"'

# IME bundle
log stream --predicate 'subsystem == "com.lingopulse.ime"'
```

Or open Console.app and filter by "LingoPulse". Verbosity is controlled by Settings → Advanced → Log level.
