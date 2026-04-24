---
title: Raycast Extension Migration (v2)
status: DECIDED — ready for /dev
created: 2026-04-24
updated: 2026-04-24
supersedes: [scripts/raycast/*.py v1]
---

# Raycast Extension Migration (v2)

> **Status:** DECIDED — ready for `/dev`
> **Created:** 2026-04-24 | **Updated:** 2026-04-24

## The Real Problem

v1 ships as Raycast Script Commands (Python files with metadata headers). Real customer pain:

1. **Dictionary's 2nd and 3rd candidates aren't clickable.** Raycast's `fullOutput` mode has no row-selection callback. First candidate auto-copies; the rest require manually highlighting text inside the Raycast panel. Customer's job is picking the *right* word — we hide 2 of 3 options.
2. **Tone picker doesn't preselect your last-used tone.** We already store `tone_overrides.json` per-app. We just can't *show* it in a static Raycast dropdown. Every override is two clicks instead of one.
3. **Install is 6 hotkey assignments + directory picker + per-binary Accessibility grant.** Each hotkey is a separate trip to Raycast preferences. You hit the Accessibility wall on first refine.
4. **HUD is limited to macOS notifications.** No inline progress that updates in-place, no error-with-retry-button, no diff rendered with color.

These aren't edge cases — they're the core Dictionary and Tone flows, plus setup day one.

## Scenarios

| Moment | What you need | What v1 delivers |
|--------|--------------|------------------|
| Dictionary returns 3 candidates, you want the second one | Click it, paste it, done | Manually highlight the word inside a Raycast panel, copy, paste |
| Tone picker in Slack where you usually pick "Professional" | "Professional" preselected, one enter | Casual is preselected (dropdown order), two clicks |
| First refinement of the day | Press ⌘⌥E, see result | Press ⌘⌥E, wait, see "osascript not allowed" error, dig through System Settings to grant Python accessibility, restart Raycast, try again |
| First day of install | One command, try it | brew install raycast + brew install ollama + ollama pull + install.sh + open Raycast → directory picker → 6 hotkeys → Accessibility prompt |

## Decision

**Migrate to a proper Raycast Extension (TypeScript) with a Python backend daemon.**

All four architectural knobs:

| Knob | Choice |
|------|--------|
| TS ↔ Python IPC | **HTTP daemon** — Python runs a localhost server, TS calls `fetch('127.0.0.1:PORT/...')` |
| Code split | **Thin TS, fat Python** — extension is pure UI; all prompts/Ollama/protection/ring-buffer stay in Python; 104 existing tests stay green |
| Preferences | **`~/.config/lingopulse/config.json` remains source of truth** — extension reads it, doesn't duplicate schema |
| Scope | **Full replacement** — delete `scripts/raycast/*.py`; extension is the only way to invoke |

## Details

### New architecture

```
┌─────────────────────┐     HTTP      ┌────────────────────────┐
│  Raycast Extension  │ ────────────> │  LingoPulse Daemon     │
│  (TypeScript)       │ <──────────── │  (Python, localhost)   │
│                     │               │                        │
│  - hotkey handlers  │               │  - Ollama client       │
│  - List, Form, Grid │               │  - prompt building     │
│  - HUD, Toast       │               │  - Cursor heuristic    │
│  - diff rendering   │               │  - ring buffer         │
│  - per-app prefs UI │               │  - history.jsonl       │
│                     │               │  - clipboard wrapper   │
│                     │               │  - protection regex    │
└─────────────────────┘               └────────────────────────┘
         │                                       │
         ▼                                       ▼
   Raycast runtime                        Ollama (localhost:11434)
```

### The Python daemon

New module: `lingopulse/daemon.py`. Runs a minimal HTTP server using `http.server` (stdlib — no new deps).

Endpoints:

| Method + Path | Body | Returns |
|---------------|------|---------|
| `POST /refine` | `{selection, app, tone_override?}` | `{original, refined, diff, ring_id}` |
| `POST /refine/undo` | `{ring_id?}` (optional; defaults to latest) | `{original}` |
| `POST /dictionary` | `{query}` | `{candidates: [{word, example, register, confidence?}...], query_language}` |
| `POST /dictionary/pick` | `{query, candidates, picked_index}` | `{picked_word}` (also logs to history) |
| `POST /capture_style` | `{text, app}` | `{saved: true}` |
| `GET /status` | — | `{healthy: true, model: "...", model_loaded: true/false}` |
| `GET /config` | — | `config.json contents` |

Design decisions for the daemon:
- **Port:** uses `:17823` by default (random unassigned port from IANA's user range). Configurable via `daemon.port` in config.json.
- **Binds to 127.0.0.1 only** — never exposed on LAN.
- **No auth** — local-only binding makes auth unnecessary for a personal tool.
- **Lifecycle:** runs as a LaunchAgent (new plist alongside the existing warmup/keepalive ones). Starts at login. Stays running; consumes ~40 MB idle. Auto-restarts if it crashes (launchd `KeepAlive`).
- **Existing Python modules are re-used wholesale.** `lingopulse/fixer.py::refine()` becomes the `/refine` handler. No logic duplication.

### The Raycast Extension

New directory: `extension/` at the project root.

```
extension/
├── package.json              # Raycast extension manifest
├── tsconfig.json
├── src/
│   ├── refine.tsx            # ⌘⌥E — Refine Selection
│   ├── preview.tsx           # ⌘⌥⇧E — Refine (Preview) with inline diff
│   ├── undo.tsx              # ⌘⌥Z — Undo Refinement
│   ├── tone-picker.tsx       # ⌘⌥T — Refine with Tone (real list, per-app preselect)
│   ├── dictionary.tsx        # ⌘⌥S — Find a Word (REAL row-selection)
│   ├── capture-style.tsx     # ⌘⌥M — Save as Style Example
│   ├── lib/
│   │   ├── api.ts            # fetch() wrapper for the Python daemon
│   │   ├── config.ts         # read ~/.config/lingopulse/config.json
│   │   ├── diff.tsx          # word-level diff renderer (React component)
│   │   └── types.ts          # shared TypeScript types (match daemon schemas)
│   └── ...
```

Each command is a Raycast `Command` export (TSX component). Raycast's `package.json` declares them — they appear in Raycast's command list on install with stock icons, and each has an individually-assignable hotkey.

Key Raycast APIs used (from [Raycast Developer docs](https://developers.raycast.com/)):
- `List` — for Dictionary (row selection works), Tone picker (per-app default via `defaultValue`)
- `Detail` — for Preview (Markdown-rendered diff inline)
- `Toast` + `showHUD` — for Fixer progress/success/error
- `Clipboard` — for the actual paste-back (Raycast handles Accessibility at the app level, one grant)
- `LocalStorage` — for per-app tone memory (replacing `tone_overrides.json` as the store — better than a file for TS)

### Install story (the v2 answer)

From clone to first ⌘⌥E working:

```bash
# Prereqs (one-time)
brew install --cask raycast
brew install ollama node
brew services start ollama

# Install
git clone <repo> ~/Projects/lingopluse && cd ~/Projects/lingopluse
./scripts/install.sh    # pulls gemma3:1b-it-qat, sets keep-alive, installs LaunchAgents (including new daemon agent)

# Extension — one command
cd extension && npm ci && npm run dev
# This opens Raycast with the extension loaded in dev mode.
# Commands appear in Raycast automatically; assign hotkeys in Raycast prefs.
```

First hotkey press → Raycast asks for Accessibility once → grant → done.

Compared to v1: no directory picker, no per-command script-shebang shenanigans, no per-Python-binary permission grant. Raycast handles Accessibility for its own extensions cleanly.

### What v1 code survives

| Area | Survives? |
|------|-----------|
| `lingopulse/config.py`, `history.py`, `ollama_client.py`, `prompts.py`, `fixer.py`, `dictionary.py`, `clipboard.py`, `apps.py`, `protection.py`, `ring_buffer.py`, `hud.py` | **Yes** — all of it, unchanged. 104 tests stay green. |
| `scripts/raycast/*.py` (6 files) | **Deleted** — replaced by the extension. |
| `scripts/install.sh`, `uninstall.sh`, `warmup_ping.sh` | **Extended** — install.sh adds the daemon LaunchAgent + `npm ci` step. |
| `launch_agents/com.lingopulse.{warmup,keepalive}.plist.template` | **Kept** — plus a new `com.lingopulse.daemon.plist.template` |
| Existing product docs in `docs/product/` | **All still authoritative** — this doc is an architectural shell over the same decisions. |

### What changes for daily use

| Daily task | v1 behavior | v2 behavior |
|-----------|-------------|-------------|
| ⌘⌥E on a selection | Refines + replaces via osascript keystroke | Refines + replaces via Raycast's Clipboard.paste() API |
| ⌘⌥S Dictionary | First candidate auto-copies; others need manual highlight | Row-selectable list; Enter on any row copies+pastes |
| ⌘⌥T Tone | Fixed dropdown order | Last-used-tone-per-app preselected; shows an empty state if no override yet |
| ⌘⌥⇧E Preview | Notification + fullOutput panel | Inline `Detail` view with Markdown diff; accept with Enter, cancel with Esc |
| ⌘⌥Z Undo | osascript keystrokes | Raycast Clipboard API; reliable across apps |

### HUD / feedback timing (unchanged policy)

The timing rules from `fixer-performance.md` (100ms show, 2s cold-start notice, 15s error) still apply. They move from the Python script's thread to the TS extension's async handlers. Config values are read from `config.json` via the daemon's `/config` endpoint.

### What does NOT change

- Ollama + model (still Gemma 3 1B (QAT), same keep-alive schedule)
- Ring buffer format + file path
- history.jsonl format + file path
- config.json schema
- Prompts (identical text, same tone tables, same Cursor heuristic)
- LaunchAgents for warmup + keepalive

## Open Questions (flag for /dev)

1. **Daemon startup ordering.** The daemon needs Ollama reachable. Daemon's LaunchAgent should have `KeepAlive = true` and retry if Ollama isn't ready — should not block on startup. If daemon starts before Ollama, first request to `/refine` does the ping-and-wait.

2. **Extension dev mode vs published.** For personal use, `npm run dev` (Raycast picks it up from source) is fine. Publishing to the Raycast Store requires their review process — out of scope for v2 unless you want public distribution.

3. **Tone picker's "Grammar-only" option** is the odd one out (not a tone, a mode). v2 might split it into its own command `⌘⌥G — Fix Grammar Only`. Discuss during /dev.

4. **Config.json hot-reload.** If user edits config.json, does the daemon need a SIGHUP handler or do they restart the daemon? For v2: daemon re-reads config on every request (cheap — it's <1 KB). Can optimize later.

5. **Python venv location in PATH.** The daemon LaunchAgent needs `.venv/bin/python`. Install.sh writes the absolute path into the plist; moving the project requires a re-run. Same story as v1's Raycast script shebangs — at least now it's in one place.

## Tasks (for /dev)

**Foundation (sequential, blocks everything):**

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 1 | Python daemon with HTTP endpoints | Backend | `curl -X POST http://127.0.0.1:17823/refine -d '{"selection":"hey","app":"Slack"}'` returns `{original, refined, diff, ring_id}`. `/status`, `/config`, `/dictionary`, `/refine/undo`, `/capture_style` all respond correctly. Uses existing `lingopulse.fixer.refine()` internally. Tests verify each endpoint's happy path + error cases. |
| 2 | Daemon LaunchAgent plist + install.sh extension | Infrastructure | After `./scripts/install.sh`, `launchctl list \| grep lingopulse.daemon` shows the daemon loaded. `curl http://127.0.0.1:17823/status` returns `healthy: true` within 5 s of login. KeepAlive restarts the daemon on crash. |
| 3 | Extension scaffold (package.json, tsconfig, preferences declaration, single "Hello" command) | Frontend | `cd extension && npm ci && npm run dev` opens Raycast with a "LingoPulse" entry visible. Running it shows "Hello from LingoPulse" toast. |

**UI commands (parallelizable after foundation):**

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 4 | `refine.tsx` — ⌘⌥E | Frontend | Selecting text in Slack and pressing the assigned hotkey replaces the text with the refined version within ~1 s warm. Toast shows word-level diff. Errors (timeout, daemon down, protection error) show specific retry-capable toasts. |
| 5 | `undo.tsx` — ⌘⌥Z | Frontend | After a refinement, pressing the assigned hotkey restores the original text exactly. If the refined text is no longer selected, shows a `List` of the last 5 originals; selecting one copies it to clipboard. |
| 6 | `preview.tsx` — ⌘⌥⇧E | Frontend | Pressing the hotkey opens a Raycast `Detail` view showing the original vs refined as a color-coded Markdown diff. Pressing Enter replaces the selection; Esc leaves it untouched. |
| 7 | `tone-picker.tsx` — ⌘⌥T | Frontend | Opens a Raycast `List` with 5 tones. The last-used tone in the current app is preselected (cursor starts on it). Selecting a tone runs the refinement. `LocalStorage` persists per-app last-used. |
| 8 | `dictionary.tsx` — ⌘⌥S | Frontend | User types a query (English or Hebrew). A `List` of up-to-3 candidates renders with word/register/example/⚠️-for-low-confidence. Enter on any row copies the word to clipboard and pastes it into the previously-active app. Hebrew detection routes to the Hebrew prompt path. |
| 9 | `capture-style.tsx` — ⌘⌥M | Frontend | Pressing the hotkey on a selection saves it to `history.jsonl` via `/capture_style` and shows "Saved as style example" toast. |

**Cleanup + docs (sequential, last):**

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 10 | Delete `scripts/raycast/*.py` and remove references | Cleanup | `scripts/raycast/` directory is gone. README no longer mentions adding a script directory in Raycast. Tests still pass (they were testing the Python modules, not the old scripts). |
| 11 | Update install.sh for extension install | Infrastructure | `./scripts/install.sh` runs `npm ci` in the extension dir as one of its steps. User-facing output tells them to run `npm run dev` once to register the extension in Raycast. |
| 12 | Update README for v2 install story | Docs | README reflects the 4-line install: brew prereqs → git clone → install.sh → npm run dev. Removes the "Add Script Directory" section. Keeps troubleshooting section with updated paths. |
| 13 | Update v1 limitation notes in existing product docs | Docs | `fixer-undo.md`, `fixer-tone-context.md`, `dictionary-correctness.md` get a "v2 NOTE" section flagging which limitations are now resolved (Dictionary row-selection, tone-picker preselection, HUD richness). Existing decisions remain valid; this is additive. |

## Hand-off

Tasks 1–13 go to `/dev`. Critical path: T1 → T2 → T3 → (T4–T9 parallel) → T10–T13. Estimated effort: 2–3 hours for a single orchestrator.

Remaining ambiguities (daemon startup ordering, grammar-only UX, venv path durability) are implementation-detail and can be resolved during dev.
