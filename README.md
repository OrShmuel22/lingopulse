# LingoPulse

LingoPulse is a local, private English refinement tool for macOS power users. It provides instant text correction and word lookup via global hotkeys, with context-aware tone adjustment based on the active app. Runs entirely offline on Apple Silicon via Ollama + Gemma 4 E4B.

---

## Requirements

- macOS 14+ (tested on M4 Air)
- Python 3.11+ (3.12 recommended)
- Ollama
- Node.js
- Raycast
- Homebrew (to install the above)

---

## Install

```bash
# Prerequisites (one-time)
brew install --cask raycast
brew install ollama node
brew services start ollama

# Install LingoPulse
git clone <repo-url> ~/Projects/lingopluse
cd ~/Projects/lingopluse
python3 -m venv .venv
.venv/bin/pip install -e .
./scripts/install.sh          # pulls gemma4:e4b, installs LaunchAgents (daemon + keep-alive)

# Register the Raycast extension (one-time)
cd extension
npm ci
npm run dev
# Leave this running — Raycast picks up the extension in dev mode.
# The six LingoPulse commands appear in Raycast automatically.
```

---

## Hotkey Setup

In Raycast → Extensions → find LingoPulse → assign hotkeys for each of the six commands:

| Hotkey | Command |
|--------|---------|
| ⌘⌥E | Refine Selection |
| ⌘⌥⇧E | Refine Selection (Preview) |
| ⌘⌥Z | Undo Refinement |
| ⌘⌥T | Refine with Tone |
| ⌘⌥S | Find a Word |
| ⌘⌥M | Save as Style Example |

---

## Accessibility

First hotkey press will prompt: "Raycast wants to control your computer using Accessibility." Click Open System Settings → toggle Raycast ON. **This is one-time, per-Mac.** Unlike v1, no per-binary grant is needed.

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

## Architecture

LingoPulse v2 has two parts:
- **Python daemon** (`lingopulse.daemon`) — a localhost HTTP server at 127.0.0.1:17823 wrapping Ollama + prompt building + ring buffer + history. Runs as a LaunchAgent.
- **Raycast extension** (`extension/`) — TypeScript UI that calls the daemon. Installed via `npm run dev`.

Config.json at `~/.config/lingopulse/config.json` is the source of truth; the extension reads it via the daemon's `/config` endpoint.

---

## Daily Flow

Select text, press ⌘⌥E. If the rewrite is bad, press ⌘⌥Z. When you want a specific tone, press ⌘⌥T. When you don't know the English word, press ⌘⌥S.

---

## Migration to a New Mac

Copy these files and re-run `./scripts/install.sh`:

```
~/.config/lingopulse/config.json
~/.config/lingopulse/history.jsonl
```

Note: `tone_overrides.json` is no longer needed — per-app tone memory moved to Raycast's LocalStorage.

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
Ollama may be loading the model cold. Run `ollama ps` — it should show `gemma4:e4b`. If the model is not listed, run `./scripts/warmup_ping.sh` to reload it. Logs at `~/Library/Logs/lingopulse-warmup.log`.

**Daemon not reachable**
Check `~/Library/Logs/lingopulse-daemon.log`. Verify `curl -sf http://127.0.0.1:17823/status` returns a response. If Ollama is down, run `brew services restart ollama`.

**Undo panel appears instead of direct undo**
You clicked away after the refinement and the refined text is no longer selected. Manually re-select the text you want to revert, then press ⌘⌥Z.

**Clipboard images or files are clobbered**
LingoPulse preserves text-only clipboard content. Non-text items (images, files) are not preserved.

---

## Honest Limitations

- The Dictionary uses Gemma 4 E4B — strong for English but can silently mistranslate Hebrew queries. See `docs/product/dictionary-correctness.md` for the revisit criteria (upgrade to Qwen 7B if picked_index >= 1 rate stays high).
- Undo requires the refined text to still be selected; otherwise the fallback panel activates.

---

## Project Structure

```
extension/           # Raycast Extension (TypeScript)
  src/
    refine.tsx       # ⌘⌥E
    undo.tsx         # ⌘⌥Z
    preview.tsx      # ⌘⌥⇧E
    tone-picker.tsx  # ⌘⌥T
    dictionary.tsx   # ⌘⌥S
    capture-style.tsx # ⌘⌥M
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
  daemon.py          # localhost HTTP server (port 17823)
scripts/
  install.sh         # idempotent installer
  uninstall.sh
  warmup_ping.sh     # Ollama keep-alive ping
launch_agents/       # plist templates
  com.lingopulse.warmup.plist.template
  com.lingopulse.keepalive.plist.template
  com.lingopulse.daemon.plist.template
docs/product/        # decision records (read these for context)
tests/               # pytest suite (116 tests)
```

---

## Contributing / Dev

Run the test suite:

```bash
.venv/bin/python -m pytest tests/
```

Product decisions are logged in `docs/product/`.
