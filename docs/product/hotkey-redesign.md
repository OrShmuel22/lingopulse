# Hotkey Redesign — Single Key + Double-Tap + Shell Widget

> Status: PLANNING
> Created: 2026-04-27 | Updated: 2026-04-27

## The Real Problem

The current entry to LingoPulse requires a two-step flow (select text → press a 3-key chord) and forces the user to memorize six chords. Selecting text in terminals (iTerm, Terminal, Cursor's terminal pane, etc.) is mouse-only because shells don't expose AX text — so for the apps where the user types most fluently, the product is effectively unreachable. Beyond that, three-finger chords like ⌘⌥E collide with app shortcuts (Slack, Chrome) and feel awkward.

**Customer view:** *"I want one quick gesture that refines what I just typed, no matter which app I'm in, without having to highlight anything."*

## Scenarios

| Moment | Customer needs | What actually happens today |
|--------|----------------|-----------------------------|
| Typing in iTerm prompt, want last command refined | Press one key, command rewritten in place | No AX → can't read field. Mouse-drag selection in terminal is impractical. Hotkey is a no-op. |
| Composing a Slack message | Press one key → whole message refined | Must press ⌘A then ⌘⌥E (where ⌘⌥E is also Slack's own shortcut for some users). Two chords. |
| Quick re-tone or undo from a Notes draft | One trigger that exposes all actions | Must remember 6 distinct chords (⌘⌥E/⇧E/Z/T/S/M). Cognitive load. |
| User binds new combo to avoid Slack collision | Combo that won't clash with any app | Any chord is a potential conflict; modifier-only triggers don't conflict. |

## Decision

Replace the six chord hotkeys with a two-trigger model + a shell-side widget for terminals.

| Trigger | Action | Where |
|---------|--------|-------|
| **Single-press Right ⌘** (modifier alone, tap and release) | Refine. If selection exists → refine selection. If no selection → grab focused field's full value via AX, refine, write back. | Any AX-aware app (Slack, Chrome, Notes, Mail, Safari, Cursor's editor pane, etc.) |
| **Double-tap ⇧** (two presses ≤ 300ms apart) | Open quick-action menu near caret: Refine · Preview · Tone · Undo · Find a Word · Capture Style. Pick by ↑↓/number/Enter. | Anywhere |
| **`lp-refine` shell widget** (user installs into zsh/bash, bound to a shell keybind of their choice — e.g. `^G`) | Refine current command-line buffer in place | iTerm, Terminal, Warp, Alacritty, any shell |

The six existing chord hotkeys are **removed entirely**. Old saved bindings cleared on upgrade.

### Why this combination

- **Modifier-only triggers don't conflict.** Right-⌘ alone has no default macOS use; double-tap ⇧ is well-known (Spotlight uses ⌘⌘, JetBrains uses ⇧⇧). Both survive every app.
- **Auto-grab solves the "select first" problem in AX apps.** The `kAXValueAttribute` read used by Live Mode already works synchronously — repurpose it for a triggered refine.
- **Shell widget is the only correct answer for terminals.** AX is gone; clipboard tricks (⌘A → ⌘C) don't reach the shell input buffer; macOS-side keystroke synthesis would clobber screen output. A localhost endpoint + `BUFFER`-aware shell function is how `fzf`, `atuin`, and similar tools handle this exact problem.
- **One menu beats six chords.** All non-primary actions live behind one trigger; users discover them in-place instead of memorizing.

### Trade-offs accepted

- Right-⌘ standalone detection requires a custom global event monitor (NSEvent.flagsChanged + state machine) because the `KeyboardShortcuts` package doesn't model modifier-only hotkeys. Adds ~80 LOC; well-trodden pattern.
- Shell widget needs a small localhost HTTP server inside the app (bound to `127.0.0.1` only, token-gated via `~/.config/lingopulse/shell-token`). New surface area, but tiny.
- "Refine entire field" can hit Ollama with longer inputs than today's selection-only flow. Existing prompt + busy-detection already handles this; worth verifying on long Slack drafts.
- Power users who memorized the chord hotkeys lose them. Migration note in onboarding + release notes; can be revisited if anyone complains, but the chord model is what we're trying to escape.

## Details

### Single-press Right ⌘

- Detect via `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`.
- State machine: on right-⌘ down (keyCode 54, command flag set), record timestamp + arm a "tap" flag. On any other keyDown while ⌘ is held → cancel tap. On right-⌘ up within ≤ 250ms with tap still armed → fire refine.
- Refine logic: try AX selection → fallback to AX field value → if both empty, show "no field focused" toast.

### Double-tap ⇧

- Same flagsChanged monitor. Track ⇧ down → up → down within ≤ 300ms.
- Fire opens quick-action panel anchored near caret (reuse `CaretLocator`).

### Quick-action menu

- New SwiftUI view, floating `NSPanel` (non-activating).
- Items: Refine · Preview · Tone · Undo · Find a Word · Capture Style.
- Number keys 1-6 jump-pick; ↑↓ + Enter; Esc dismiss.
- Reuses existing command classes (`PreviewCommand`, `ToneCommand`, etc.) — no duplicate logic.

### Shell widget

- App embeds a tiny HTTP server (`Network.framework` `NWListener` on 127.0.0.1, ephemeral port, written to `~/.config/lingopulse/shell.sock` or `shell.port`).
- Endpoint: `POST /refine` with `{ "text": "..." }` → `{ "refined": "..." }`. Bearer token from `~/.config/lingopulse/shell-token` (generated on first run, mode 0600).
- Distribute `lp-refine` shell function via `app/scripts/lp-refine.zsh` and `lp-refine.bash`. User adds `source ~/.config/lingopulse/lp-refine.zsh` + `bindkey '^G' lp-refine` (zsh ZLE widget).
- Widget reads `$BUFFER` (zsh) or `READLINE_LINE` (bash readline), POSTs, replaces buffer.
- Settings tab gains a "Shell integration" section with one-click "Install for zsh / bash" buttons that write the source line + bindkey snippet to the right rc file (with confirmation).

### Removal of chord hotkeys

- Delete the 6 `KeyboardShortcuts.Name` entries in `HotkeyManager.swift`.
- Remove `HotkeyTab` from `SettingsWindow.swift`.
- On upgrade: clear stored shortcuts via `KeyboardShortcuts.reset(...)` once, gated by a `lp.hotkeyMigration_v2` flag.

### Settings additions

- New "Triggers" tab:
  - Single-key picker: Right ⌘ (default) · Right ⌥ · Fn · Caps Lock (with hidutil note).
  - Double-tap modifier picker: ⇧ (default) · ⌘ · ⌥.
  - Shell integration installers + token regeneration button.

### Onboarding update

- Replace "Six hotkeys" step with: "Press Right ⌘ to refine — anywhere. Double-tap ⇧ for the menu. For Terminal, install the shell helper (one click)."
- Mention the no-selection-needed superpower explicitly.

## Tasks

| # | Task | Area | DOD |
|---|------|------|-----|
| 1 | Build modifier-event monitor service | Service | A `TriggerMonitor` class detects single-press right-⌘ (≤250ms, no other keys) and double-tap ⇧ (≤300ms gap). Unit tests cover: clean tap, tap with other key (rejected), held-too-long (rejected), double-tap window edges. |
| 2 | Wire single-press right-⌘ to refine | Coordinator | Pressing and releasing right-⌘ alone in Notes, Slack, Chrome address bar, and Mail with no selection refines the entire field's value. With a selection, refines just the selection. With no focused field, shows a toast. |
| 3 | Wire double-tap ⇧ to quick-action menu | Coordinator | Tapping ⇧⇧ in any app opens a floating panel anchored near the caret. |
| 4 | Build quick-action panel view | Views | Floating panel lists 6 actions (Refine, Preview, Tone, Undo, Find a Word, Capture Style). 1-6 / arrows / Enter pick; Esc dismisses; click-outside dismisses. Picks dispatch to existing command classes. |
| 5 | Embed local HTTP server for shell widget | Service | `127.0.0.1` listener on ephemeral port, `POST /refine` with bearer-token auth returns refined text using `Fixer`. Token written to `~/.config/lingopulse/shell-token` (mode 0600). Port written to `shell-port`. Refuses connections without matching token. |
| 6 | Ship `lp-refine` zsh/bash widgets | Shell | `app/scripts/lp-refine.zsh` and `.bash` exist. After running install, pressing the bound key (default `^G`) inside iTerm/Terminal replaces the current command line with the refined version, with the cursor at end. |
| 7 | Add "Install for shell" buttons to Settings | Settings | Settings → Triggers → Shell integration has one-click installers for zsh and bash that append the source/bindkey lines to the user's rc file (with a confirmation dialog showing the exact lines). Idempotent: re-running doesn't duplicate. |
| 8 | Remove 6 chord hotkeys + migration | Cleanup | `HotkeyManager.swift` no longer registers the 6 chords. `HotkeyTab` removed from Settings. On first launch after upgrade, stored shortcuts are cleared (one-shot, gated by migration flag). |
| 9 | Update Onboarding | Onboarding | New "How to use" step replaces the chord list with: Right-⌘ for refine, ⇧⇧ for menu, "Install shell helper" button for terminal users. |
| 10 | Update Settings → Triggers | Settings | New tab lets the user pick single-key (Right ⌘ / Right ⌥ / Fn / Caps Lock) and double-tap modifier (⇧ / ⌘ / ⌥). Selection persists across launches. |
| 11 | Documentation: README rewrite | Docs | README "Hotkeys" table replaced with the new two-trigger model and shell-widget section. v1 chord hotkeys mentioned only under "Migration from v1.x". |
| 12 | Long-input safety check on auto-grab | Refine | Refining a focused field with > 4000 chars either truncates with a toast or proceeds without OOM. Verified on a long Slack draft and a long Mail body. |
