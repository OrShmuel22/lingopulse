# LingoPulse macOS App

Native menu-bar app. Calls the existing Python daemon at `http://127.0.0.1:17823`.

## Status: Phase 2 skeleton

What works:
- Menu bar icon + menu (Refine / Status / Quit)
- Global hotkey ⌘⌥E
- Reads selection via macOS Accessibility API
- POSTs to daemon `/refine`, gets structured edits back
- Writes refined text back to focused element via AX (clipboard fallback)
- Logs all actions via `NSLog`

What's NOT here yet:
- Floating chip UI (Phase 3)
- Live AX listener (Phase 3)
- Tab-to-accept overlay (Phase 4)
- Personal dictionary UI (Phase 5)
- Settings window (Phase 6)

## Build

Requires Swift 5.9+ (Xcode CLT or full Xcode), macOS 14+.

```bash
cd app
./scripts/build-bundle.sh debug         # builds + bundles + ad-hoc signs
open LingoPulse.app                     # launches as menu-bar app
```

The bundle is ad-hoc signed so Accessibility permission persists across rebuilds.

## First-run permission grant

1. Launch `LingoPulse.app`
2. macOS prompts: "LingoPulse wants control via Accessibility"
3. System Settings → Privacy & Security → Accessibility → toggle ON
4. Quit + relaunch

If prompt doesn't appear, manually add `LingoPulse.app` in System Settings → Privacy → Accessibility.

## Architecture

```
LingoPulseApp (menu bar, .accessory activation policy)
├─ AppDelegate          launches subsystems
├─ MenuBarController    NSStatusItem + menu items
├─ HotkeyManager        Carbon EventHotKey, ⌘⌥E → coordinator
├─ AXClient             readSelection + writeFocusedValue
├─ DaemonClient         async URLSession → localhost:17823
└─ AppCoordinator       wires hotkey + AX + daemon
```

Daemon contract (Phase 1, already shipped): see `lingopulse/daemon.py`.

## Daily use

1. Launch `LingoPulse.app` (it stays running, menu bar icon ✏️)
2. Select text in any app
3. Press ⌘⌥E (or click menu bar → Refine Selection)
4. Refined text replaces selection
5. Console log shows edits + categories — view via `Console.app` filtered by "LingoPulse"

## Console logs

```bash
log stream --predicate 'eventMessage CONTAINS "LingoPulse"'
```

## Known limits (Phase 2)

- No live listener — must press hotkey
- No floating UI — refine pastes silently
- AX write may fail in some apps (Slack desktop, browsers) — clipboard fallback used
- No streaming — full response wait
- No settings UI — daemon URL hardcoded
