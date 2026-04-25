# LingoPulse macOS App — v1

Native menu-bar app that watches your typing and suggests grammar / style fixes via the local daemon at `http://127.0.0.1:17823`.

## Build

Requires Swift 5.9+ (Xcode CLT or full Xcode), macOS 14+.

```bash
cd app
swift build                             # compile only
./scripts/build-bundle.sh debug         # builds + bundles + ad-hoc signs → LingoPulse.app
open LingoPulse.app
```

Ad-hoc signing lets Accessibility permission persist across rebuilds without re-prompting.

## First-run permissions

### Accessibility (required)

1. Launch `LingoPulse.app`
2. macOS prompts "LingoPulse wants to control this computer"
3. System Settings → Privacy & Security → Accessibility → toggle LingoPulse ON
4. Quit and relaunch

If no prompt appears, add `LingoPulse.app` manually in System Settings → Privacy → Accessibility.

### Notifications (optional)

macOS will ask once for notification permission. Grant it to receive cold-start and daemon-down alerts.

## Features

1. **Live suggestions** — chip appears automatically after you pause typing (debounce 1.5s default). Works in all apps except terminals.
2. **Manual refine** — press ⌘⌥G (or menu bar → Refine Selection) to refine selected text on demand.
3. **Personal dictionary** — words/phrases you add are never flagged. Per-app or global scope.
4. **Import / Export** — back up and restore your personal dictionary as JSON.
5. **Settings** — configure daemon URL, debounce, auto-dismiss, hotkey, excluded apps, log level.
6. **Never-fix context menu** — right-click any strikethrough word in the chip to permanently ignore it.

## Hotkeys

| Hotkey | Action |
|--------|--------|
| ⌘⌥G | Manual refine (configurable in Settings → Hotkey) |
| ⌘D | Open Personal Dictionary |
| ⌘, | Open Settings |

## Chip controls

| Key | Action |
|-----|--------|
| Tab | Accept current edit and advance to next |
| Esc | Dismiss chip, send feedback |
| ↓ / ↑ | Cycle through edits |

## Troubleshooting

**No chip appears / "AX denied"**
- Check System Settings → Privacy → Accessibility — LingoPulse must be toggled ON.
- Some apps (Electron, some browsers) block AX writes; manual refine will fall back to clipboard paste.

**"Daemon unreachable" notification**
- Ensure the daemon is running: `launchctl list | grep lingopulse`
- Start it manually: `cd lingopulse && python daemon.py` or via the launchd plist.
- Default URL is `http://127.0.0.1:17823` — change in Settings → General if needed.

**Hotkey not working**
- Another app may have registered the same combination. Change it in Settings → Hotkey.
- Quit and relaunch after changing the hotkey.

**View logs**

```bash
log stream --predicate 'eventMessage CONTAINS "LingoPulse"'
```

Or open Console.app and filter by "LingoPulse". Verbosity is controlled by Settings → Advanced → Log level.
