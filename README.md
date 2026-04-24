# LingoPulse

LingoPulse is a local, private English refinement tool for macOS power users. It provides instant text correction and word lookup via global hotkeys, with context-aware tone adjustment based on the active app. Runs entirely offline on Apple Silicon via Ollama + Gemma 3 4B.

---

## Requirements

- macOS 14+ (tested on M4 Air)
- Python 3.11+ (3.12 recommended)
- Ollama
- Raycast
- Homebrew (to install the above)

---

## Install

```bash
# 1. Install dependencies
brew install --cask raycast
brew install ollama
brew services start ollama

# 2. Clone and set up
git clone <repo-url> ~/Projects/lingopluse
cd ~/Projects/lingopluse
python3 -m venv .venv
.venv/bin/pip install -e .

# 3. Run installer (pulls model, configures LaunchAgents, sets OLLAMA_KEEP_ALIVE)
./scripts/install.sh

# 4. Add Raycast scripts
# Open Raycast → Extensions → Script Commands → Add Script Directory
# Point to: ~/Projects/lingopluse/scripts/raycast
```

---

## Hotkey Setup

Assign these hotkeys in Raycast (Extensions → Script Commands → select command → set hotkey):

| Hotkey | Command | What it does |
|--------|---------|--------------|
| ⌘⌥E | Refine Selection | Refine selected text using the app's default tone |
| ⌘⌥⇧E | Refine Selection (Preview) | Refine + show a rich diff panel (⌘⌥Z to undo) |
| ⌘⌥Z | Undo Refinement | Restore the original text (requires refined text still selected) |
| ⌘⌥T | Refine with Tone | Pick a tone (Casual/Neutral/Technical/Professional/Grammar-only) and refine |
| ⌘⌥S | Find a Word | Search by concept — English or Hebrew query, returns 3 candidates |
| ⌘⌥M | Save as Style Example | Log the selection as a style example for future personalization |

---

## Config

Config lives at `~/.config/lingopulse/config.json`. Missing keys fall back to built-in defaults — you only need to include what you want to override.

Default tone mappings (from `lingopulse/config.py`):

| App | Default tone |
|-----|-------------|
| Slack, Discord, Messages | Casual |
| Mail, Outlook, Linear | Professional |
| Cursor, VS Code | auto (Technical if code context detected) |
| Notes | Neutral |
| Everything else | Neutral |

For detailed config schemas see:
- `docs/product/fixer-tone-context.md` — tone detection and `app_map`
- `docs/product/fixer-performance.md` — keepalive, timeout tuning
- `docs/product/fixer-undo.md` — ring buffer config
- `docs/product/dictionary-correctness.md` — dictionary model config

---

## Daily Flow

Select text, press ⌘⌥E. If the rewrite is bad, press ⌘⌥Z. When you want a specific tone, press ⌘⌥T. When you don't know the English word, press ⌘⌥S.

---

## Migration to a New Mac

Copy these files and re-run `./scripts/install.sh`:

```
~/.config/lingopulse/config.json
~/.config/lingopulse/history.jsonl
~/.config/lingopulse/tone_overrides.json
```

Do NOT copy `~/.cache/lingopulse/` — it is session state and regenerates automatically.

---

## Uninstall

```bash
./scripts/uninstall.sh
```

Removes LaunchAgents. Preserves all user data under `~/.config/lingopulse/`.

---

## Troubleshooting

**"Refinement timed out"**
Ollama may be loading the model cold. Run `ollama ps` — it should show `gemma3:4b-it-qat`. If the model is not listed, run `./scripts/warmup_ping.sh` to reload it. Logs at `~/Library/Logs/lingopulse-warmup.log`.

**Hotkey does nothing**
Check that `~/Projects/lingopluse/scripts/raycast` is listed as a script directory in Raycast → Extensions → Script Commands.

**Shebang error after moving the project**
The scripts hardcode `/Users/orshmuel/Projects/lingopluse/.venv/bin/python` in their shebangs. If you have cloned to a different path, run this from the project root:

```bash
find scripts/raycast -name '*.py' -exec sed -i '' "1s|.*|#!$(pwd)/.venv/bin/python|" {} \;
```

**Undo panel appears instead of direct undo**
You clicked away after the refinement and the refined text is no longer selected. Manually re-select the text you want to revert, then press ⌘⌥Z.

**Dictionary candidates 2 and 3 are not clickable**
Raycast's fullOutput panel has no row callback in v1. The first candidate auto-copies to clipboard. For the other candidates, manually select the word text from the Raycast panel and copy it.

**Tone picker does not remember my last choice visually**
Raycast's dropdown is static (v1 limitation). The per-app override is stored in `tone_overrides.json`, but the dropdown always renders Casual/Neutral/Technical/Professional/Grammar-only in the same order.

**Clipboard images or files are clobbered**
LingoPulse preserves text-only clipboard content. Non-text items (images, files) are not preserved.

---

## Honest Limitations

- The Dictionary uses Gemma 3 4B Q4 — strong for English but can silently mistranslate Hebrew queries. See `docs/product/dictionary-correctness.md` for the revisit criteria (upgrade to Qwen 7B if picked_index >= 1 rate stays high).
- Shebangs are hardcoded to the install path. Moving the project requires patching them (see Troubleshooting above).
- Undo requires the refined text to still be selected; otherwise the fallback panel activates.
- Tone picker dropdown does not preselect the per-app last-used tone (Raycast static dropdown limitation).

---

## Project Structure

```
lingopulse/          # Python package (core library)
  config.py          # config loader + defaults
  history.py         # jsonl log
  ollama_client.py   # Ollama HTTP + concurrency lock
  clipboard.py       # text-only save/restore
  protection.py      # URL/code-block regex protection
  apps.py            # frontmost + selection + paste via osascript
  ring_buffer.py     # 5-slot undo buffer
  hud.py             # macOS notifications + diff rendering
  prompts.py         # tone table + Fixer prompt template + Cursor heuristic
  dictionary.py      # Hebrew detection + JSON parsing
  fixer.py           # unified refine() entry point
scripts/
  install.sh         # idempotent installer
  uninstall.sh
  warmup_ping.sh     # Ollama keep-alive ping
  raycast/           # Raycast Script Commands
    fixer.py         # ⌘⌥E
    undo.py          # ⌘⌥Z
    preview.py       # ⌘⌥⇧E
    tone_picker.py   # ⌘⌥T
    dictionary.py    # ⌘⌥S
    capture_style.py # ⌘⌥M
launch_agents/       # plist templates
docs/product/        # decision records (read these for context)
tests/               # pytest suite (104 tests)
```

---

## Contributing / Dev

Run the test suite:

```bash
.venv/bin/python -m pytest tests/
```

Product decisions are logged in `docs/product/`.
