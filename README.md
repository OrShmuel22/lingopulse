# LingoPulse

Local, private English refinement for macOS. One menu-bar app. Two triggers. Optional live-typing mode. Runs entirely offline on Apple Silicon via Ollama + Gemma 3 1B (QAT).

---

## Requirements

- macOS 14+ (tested on M4 Air)
- Apple Silicon
- [Ollama](https://ollama.com)

---

## Install

```bash
# 1. Install Ollama (one-time)
brew install ollama
brew services start ollama

# 2. Pull the model (one-time, ~800MB)
ollama pull gemma3:1b-it-qat

# 3. Open LingoPulse.app
open ~/Downloads/LingoPulse.dmg     # or wherever you put the DMG
# Drag LingoPulse to Applications
open /Applications/LingoPulse.app

# 4. Grant Accessibility when prompted, then click "I Granted — Restart LingoPulse"
```

That's it. No terminal, no Python, no LaunchAgents.

---

## Triggers

| Trigger | Action |
|---------|--------|
| **Right ⌘** (single tap) | Refine. Uses your selection if any; otherwise refines the whole focused field. |
| **Double-tap ⇧** | Open the quick-action menu (Refine · Preview · Tone · Undo · Find a Word · Capture Style). |
| **`lp-refine`** (shell widget) | Refine the current zsh/bash command line in place. |

Pick a different single key (Right ⌥, Fn) or different double-tap modifier (⌘, ⌥) in Settings → Triggers.

---

## Terminal (zsh / bash)

Live Mode and Right ⌘ don't work in iTerm/Terminal/Cursor's terminal pane — these apps don't expose AX text. Instead, install the shell widget:

1. Settings → Triggers → enable **Shell integration**.
2. Click **Install for zsh** (or bash). LingoPulse appends two lines to your `~/.zshrc`:
   ```
   source "${HOME}/.config/lingopulse/lp-refine.zsh"
   bindkey '^G' lp-refine
   ```
3. Open a new terminal (or `source ~/.zshrc`).
4. Type a sentence at the prompt and press **Ctrl+G** — the line is replaced with the refined version in place.

Bound to Ctrl+G by default. Re-bind by editing the `bindkey` line.

---

## Live Mode (optional, default OFF)

Settings → Live Mode → Enable. While typing in any AX-aware text field, LingoPulse refines after you pause for 800ms and offers an inline overlay. Apply with Enter, dismiss with Esc. 1Password and terminals are excluded by default.

---

## Daily flow

Press Right ⌘ to refine what you're writing — selection or whole field. Hit Esc to undo from the menu (double-tap ⇧). Want a specific tone? Double-tap ⇧ → Tone. In a terminal? Press Ctrl+G after installing the shell widget.

---

## Config

`~/.config/lingopulse/config.json` is the source of truth. Defaults are sensible — only override what you want to change.

User data:
- `~/.config/lingopulse/history.jsonl` — every refinement (audit log)
- `~/.config/lingopulse/style_examples.jsonl` — captured style examples
- `~/.cache/lingopulse/ring.json` — last 5 refines for undo

---

## Architecture

Single Swift menu-bar app at `app/`. In-process: Ollama HTTP client, prompt building, ring buffer, history, AX text monitor (Live Mode). No daemon. No Python. No Raycast.

```
app/Sources/LingoPulseApp/
  Services/        # OllamaService, Fixer, AppConfig, Prompts, Protection,
                   # HistoryStore, RingBuffer, ToneOverrides, AccessibilityService,
                   # SelectionService, ClipboardService, Dictionary,
                   # StyleExamplesStore, LiveTextMonitor, CaretLocator
  Commands/        # Refine, Undo, Preview, Tone, Dictionary, CaptureStyle
  Views/           # PreviewPanel, TonePickerPanel, DictionaryPanel,
                   # UndoFallbackPanel, GhostOverlayWindow
  AppDelegate, AppCoordinator, TriggerMonitor, MenuBarController,
  SettingsWindow, OnboardingWindow, Preferences, ...
docs/product/      # decision records
```

---

## Build from source

```bash
cd app
swift build --configuration release
./scripts/build-bundle.sh release    # produces app/LingoPulse.app
./scripts/build-dmg.sh release        # produces app/LingoPulse-<version>.dmg
```

---

## Migrate from a v1 install (Python + Raycast)

Run once, then forget v1:

```bash
launchctl bootout "gui/$(id -u)/com.lingopulse.warmup" 2>/dev/null
launchctl bootout "gui/$(id -u)/com.lingopulse.keepalive" 2>/dev/null
launchctl bootout "gui/$(id -u)/com.lingopulse.daemon" 2>/dev/null
rm -f ~/Library/LaunchAgents/com.lingopulse.*.plist
launchctl unsetenv OLLAMA_KEEP_ALIVE 2>/dev/null
```

Your `~/.config/lingopulse/` data carries over verbatim.

---

## Honest limits

- Hebrew dictionary uses Gemma 3 1B (QAT) — strong but not perfect on rare words
- Live Mode and Right ⌘ don't fire in iTerm/Terminal/Cursor's terminal pane (no AX text). Use the `lp-refine` shell widget instead — see Terminal section.
- Apple Intelligence Writing Tools is NOT used (no Hebrew support as of macOS 26.1)

---

## Tests

```bash
cd app
swift test     # 96 unit tests
```

---

## Migration from v1.x (chord hotkeys)

v2 replaces the six chord hotkeys (⌘⌥E and friends) with Right ⌘ + double-tap ⇧. Saved chord bindings are cleared automatically on first launch — no action needed.

---

## Uninstall

```bash
rm -rf /Applications/LingoPulse.app
rm -rf ~/.config/lingopulse ~/.cache/lingopulse
```
