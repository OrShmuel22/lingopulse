---
title: Fixer — Irreversibility & Undo
status: DECIDED
created: 2026-04-24
updated: 2026-04-24
related_problems: [B2, M3, F1, F3]
---

# Fixer — Irreversibility & Undo

> **Status:** DECIDED — ready for `/dev`
> **Created:** 2026-04-24 | **Updated:** 2026-04-24

## The Real Problem

You hit `Cmd+Opt+E`, the model mangles your message in a way you don't catch immediately, and your original wording is gone. After one or two silent failures, you stop trusting the hotkey and go back to typing by hand — the tool gets abandoned within a week.

The spec's "automatically replace the selected text" is one-way. `Cmd+Z` is unreliable across Slack web, Gmail web, Cursor, and native Mail because Accessibility-API insertions frequently don't produce an undo entry. There is no recovery path, no preview, and no guard against a double-press making drift-of-drift.

## Scenarios

| Moment | What you need | What the spec delivers |
|--------|---------------|-----------------------|
| Slack: "let's deploy the **canary** first, then **ramp** traffic" | Grammar polish, technical terms preserved | Model rewrites canary→test version, ramp→increase. Tom replies "what test version?" Original phrasing unrecoverable. |
| Mail: 4-line nuanced bug report, select-all | Same meaning, cleaner English | Model compresses to 2 lines, drops a clause. No way to know what was lost. |
| Mid-press regret: hotkey fired, then you remember you wanted to add a sentence | Abort | Can't abort. Paste lands. You reconstruct. |
| Second press because the first felt slow | Safe no-op or recovery | Second press refines the refined text → drift-of-drift, no anchor to the original. |

## Decision

**Option D: auto-replace + in-memory ring buffer + dedicated rollback hotkey + subtle diff toast + opt-in preview escape hatch.**

Specifically:

- **`Cmd+Opt+E`** — fire-and-forget as today. Before replacement, save `(original_text, app_name, cursor_position, timestamp, refined_text)` to a 5-slot in-memory ring buffer.
- **`Cmd+Opt+Z`** — rollback. Uses the ring buffer; does not rely on OS undo. Selects the refined text by length and types the original back.
- **`Cmd+Opt+Shift+E`** — opt-in preview for important messages. Shows the diff in a Raycast panel, `Enter` accepts, `Esc` dismisses.
- **Diff toast** — subtle Raycast HUD, color-coded diff, 5s auto-dismiss, with hint "⌘⌥Z to undo." Passive learning for free; never blocks typing.

### Why this model (not the alternatives)

- **Option A (always preview)** adds a keypress per use and breaks "invisible" — you stop reaching for it.
- **Option B (rely on OS `Cmd+Z`)** breaks on ~1 in 3 apps. Same failure mode as doing nothing.
- **Option C (hybrid by length)** has two mental models and still fails on short, important messages.

Option D is the only one that keeps the sub-second invisible flow for the 95% case while making every mistake recoverable by a single keystroke — *and* absorbs the F1 spec contradiction (preview vs. auto-replace) and F3 (second-press drift) for free.

## Details

### Ring buffer

- **Size:** 5 entries, FIFO eviction.
- **Storage:** in-memory (Raycast script's parent process, or a small daemon if Raycast kills the script between invocations — see Open Questions).
- **Lifetime:** session only. Resets on Raycast restart / laptop reboot. This is intentional — if you realize a rewrite was wrong the next day, the message is already sent; persistence adds complexity without solving a real scenario.
- **Entry schema:**
  ```json
  {
    "original": "string",
    "refined": "string",
    "app": "Slack",
    "timestamp": "ISO-8601",
    "cursor_hint": { "line": int, "col": int } // best-effort, may be null
  }
  ```

### Rollback flow (`Cmd+Opt+Z`)

1. Pop latest buffer entry.
2. Locate the refined text: search the active text field for an exact match of `refined` (usually the most recently inserted block).
3. Select it (`length(refined)` characters starting at the match).
4. Type `original` via Accessibility API.
5. Show HUD toast: "Reverted — original restored."

Fallback if refined text can't be located (user already edited or deleted it): show a Raycast panel with the last 5 originals, copy-to-clipboard on selection. User pastes manually.

### Diff toast

- Color-coded inline diff (word-level), truncated if longer than ~40 words.
- Displayed via Raycast HUD.
- Dismisses after 5s or on any keystroke.
- Does **not** steal focus — typing continues uninterrupted.
- Toast text ends with faint hint: `⌘⌥Z to undo`.

### Preview escape hatch (`Cmd+Opt+Shift+E`)

- Same pipeline, but instead of auto-replacing, shows the refined text + diff in a Raycast detail view.
- `Enter` → accept and replace. `Esc` → cancel, original untouched.
- Intended for: formal email to manager, legal messages, long careful drafts. You opt in per-message; no blanket UX tax.

### Concurrency guard (absorbs F2 and F3)

- A simple in-memory lock during inference. A second `Cmd+Opt+E` press while one is in flight shows a HUD "Already refining…" and is ignored.
- A press on text that exactly matches a `refined` entry in the buffer within the last 30s shows HUD "Already refined — press ⌘⌥Z to undo" and is ignored. (Covers the "I hit it twice thinking it failed" case.)

## Open Questions (flag for /dev)

1. **Process model:** Raycast Script Commands run as short-lived subprocesses. An in-memory ring buffer won't survive between presses unless we use a small long-running daemon (launchd agent) that Raycast talks to via IPC (unix socket or HTTP localhost). Decide during /dev whether to keep state in `~/.cache/lingopulse/ring.json` (file-backed, simpler) or a daemon (cleaner, warmer). File-backed is probably fine given 5 small entries.
2. **Text-injection method:** Accessibility API's `AXSelectedText` replacement works natively but fails in some Electron apps. Fallback: `pbpaste` → keystroke `Cmd+V`. Needs testing matrix: Slack desktop, Slack web, Gmail, Apple Mail, Cursor, VS Code, Notes, Messages.
3. **Where exactly does the diff toast render?** Raycast's HUD is single-line. A multi-line diff probably needs a small custom `AppKit` floating window or a Raycast "detail view" that stays passive. Decide during /dev.

## Tasks (for /dev)

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 1 | Implement ring buffer with file-backed persistence | Backend / Python | When I press `Cmd+Opt+E` on 6 messages in a row, the 6th overwrites the 1st, and reading the buffer file shows the 5 most recent entries with original, refined, app, timestamp, cursor_hint. |
| 2 | Implement Fixer hotkey `Cmd+Opt+E` with buffer-write-before-paste | Integration | When I select text in Slack and press `Cmd+Opt+E`, the text is refined and replaced **and** a new buffer entry is present containing my exact original text. |
| 3 | Implement rollback hotkey `Cmd+Opt+Z` using ring-buffer replay | Integration | When I just refined a message and press `Cmd+Opt+Z`, the refined text disappears and my exact original text is in its place in the same app. Works in Slack desktop, Slack web, Gmail, Apple Mail, and Cursor chat. |
| 4 | Implement rollback fallback (clipboard recovery panel) | UX | If I edit or delete the refined text and then press `Cmd+Opt+Z`, Raycast opens a panel showing the last 5 originals; picking one copies it to clipboard and I can paste manually. |
| 5 | Implement subtle diff HUD toast (5s auto-dismiss) | UX | After a refinement, a non-focus-stealing toast appears showing word-level diff with color, includes "⌘⌥Z to undo" hint, fades after 5s or on keystroke, and does not interrupt my typing. |
| 6 | Implement preview-mode hotkey `Cmd+Opt+Shift+E` | Integration | When I press `Cmd+Opt+Shift+E`, a Raycast detail view opens showing original + refined + diff. `Enter` replaces the text, `Esc` leaves the original untouched in the source app. |
| 7 | Implement inference concurrency lock | Backend | If I press `Cmd+Opt+E` twice within 2 seconds, only one inference runs; the second press shows HUD "Already refining…" and exits without queuing. |
| 8 | Implement "already refined" detection on re-press | Backend | If I press `Cmd+Opt+E` on text that exactly matches a `refined` entry in the buffer within the last 30s, no re-refinement runs; a HUD "Already refined — ⌘⌥Z to undo" appears. |
| 9 | Test matrix for text injection reliability | QA | `docs/product/fixer-test-matrix.md` exists, listing pass/fail for refine + undo in each of: Slack desktop, Slack web, Gmail web, Apple Mail, Cursor (code + chat), VS Code, Notes, Messages. Any failures have a documented fallback. |

## Hand-off

Next: `/dev` consumes Tasks 1–9 above. All decisions locked. Remaining ambiguity is implementation-detail only (daemon vs file-backed state, injection API fallback) and can be resolved during development without product input.
