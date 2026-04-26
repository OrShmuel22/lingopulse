# LingoPulse

Local, private English refinement for macOS. One menu-bar app. Six global hotkeys. Optional live-typing mode. Runs entirely offline on Apple Silicon via Ollama + Gemma 3 1B (QAT).

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

## Hotkeys (default)

| Hotkey  | Command                |
|---------|------------------------|
| ⌘⌥E    | Refine selection       |
| ⌘⌥⇧E   | Refine — Preview first |
| ⌘⌥Z    | Undo last refinement   |
| ⌘⌥T    | Refine with chosen tone |
| ⌘⌥S    | Find a word (dictionary) |
| ⌘⌥M    | Save selection as style example |

Rebind any of these via Settings → Hotkeys.

---

## Live Mode (optional, default OFF)

Settings → Live Mode → Enable. While typing in any AX-aware text field, LingoPulse refines after you pause for 800ms and offers an inline overlay. Apply with Enter, dismiss with Esc. 1Password and terminals are excluded by default.

---

## Daily flow

Select text, press ⌘⌥E. Bad rewrite? ⌘⌥Z. Want a specific tone? ⌘⌥T. Don't know the English word? Type a description in any language, ⌘⌥S.

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
  AppDelegate, AppCoordinator, HotkeyManager, MenuBarController,
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
- Live Mode does not fire in iTerm/Terminal/etc. — they don't expose AX text
- Apple Intelligence Writing Tools is NOT used (no Hebrew support as of macOS 26.1)

---

## Tests

```bash
cd app
swift test     # 96 unit tests
```

---

## Uninstall

```bash
rm -rf /Applications/LingoPulse.app
rm -rf ~/.config/lingopulse ~/.cache/lingopulse
```
