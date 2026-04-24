---
title: Fixer — Tone & Context (app ≠ tone)
status: DECIDED
created: 2026-04-24
updated: 2026-04-24
related_problems: [B4, M5]
---

# Fixer — Tone & Context

> **Status:** DECIDED — ready for `/dev`
> **Created:** 2026-04-24 | **Updated:** 2026-04-24

## The Real Problem

The spec maps frontmost app → tone. That mapping treats app as a deterministic signal, but it isn't. Two specific mismatches exist in the spec as written:

- **Cursor** is mapped to "technical/imperative/documentation-style." Half of Cursor typing happens in the AI chat panel — casual prose. The spec default mangles it.
- **Slack** is mapped to "casual/lowercase." Sometimes you write to your manager about a legal issue, or post in an escalation channel. The spec default strips seriousness.
- **Mail** is mapped to "professional." Wrong for a quick "running late, grabbing a taxi" to family.

The failure is silent — you don't always catch the tone mismatch until the recipient reacts.

## Scenarios

| Moment | What you need | What the spec delivers |
|--------|---------------|-----------------------|
| Slack DM to manager about legal/compliance issue | Keep serious tone, polish grammar | Casual/lowercase strips seriousness |
| Cursor AI chat: "hey can we pair on this bug" | Casual polish | "Imperative documentation style" → reads like a work order |
| Cursor editor: commit message for a perf fix | Technical + imperative | ✅ correct |
| Mail to family: "running late" | Keep casual | Formalized into "I wanted to let you know…" |
| Slack message with technical acronyms | Preserve terms, slight polish | Casual lowercasing may break precision |

## Decision

Three layers, in order of how often they fire:

1. **Smarter prompt (E).** App is a *default* signal, not a command. Prompt tells the model to preserve the original text's formality/register when it's clearly set.
2. **Tone picker hotkey (T).** `Cmd+Opt+T` opens a Raycast list — Casual / Neutral / Technical / Professional / Grammar-only — runs the refinement with that tone. Remembers last-picked **per app** so the second override in Slack is preselected.
3. **Cursor code-vs-prose heuristic.** When the app is Cursor, the selection is classified as code or prose before picking a tone. Code → technical. Prose → casual.

Plus: the app-to-tone map lives in `~/.config/lingopulse/config.json` and is user-editable.

### Why this combo (alternatives considered)

- **E only:** relies entirely on gemma4:e4b's self-judgment. Small model, inconsistent. Silent failures on edge cases.
- **T only:** spec defaults stay wrong; you have to remember to override. Forgetting = silent failure.
- **E + T + C (full Accessibility scraping of channel names, Slack/Cursor internals):** smartest defaults, but fragile. Slack UI changes break it. Privacy-adjacent. Too much work for a personal tool v1.

## Details

### The reworked prompt

The Fixer system prompt template becomes:

```
You are a careful English editor. The user typed this message in {APP_NAME}.
Typical register for this app is: {APP_DEFAULT_TONE}.

BUT: if the original message shows clear signals of a different register —
full sentences and formal address (→ preserve formal), legal/compliance
language (→ preserve serious), technical acronyms or code identifiers (→
preserve technical) — adjust to match the user's intent rather than the
app default.

Do not change the meaning. Do not add, remove, or rephrase content beyond
what's needed for clarity and correctness. Preserve all technical terms,
code identifiers, URLs, and proper nouns verbatim.

Message:
---
{SELECTION}
---

Return only the refined message. No preamble, no explanation.
```

Two guarantees from this prompt:
- Content preservation is an explicit instruction (handles B5 too — code/URL passthrough).
- The app default is a *suggestion*, not an override of the author's clearly-set tone.

### Tone picker (`Cmd+Opt+T`)

- Opens a Raycast list with 5 options:
  - Casual (lowercase-friendly, friendly)
  - Neutral (balanced clarity and grammar)
  - Technical (precise, imperative, code/documentation-aware)
  - Professional (structured business English)
  - Grammar-only (no tone shift, fix errors only)
- Select → refinement runs with that tone override.
- Same ring-buffer / undo / diff-toast pipeline as `Cmd+Opt+E` (from `fixer-undo.md`).
- **Per-app memory:** stored in `~/.config/lingopulse/tone_overrides.json`:
  ```json
  {
    "Slack": "Professional",
    "Mail": "Casual",
    "Cursor": "Neutral"
  }
  ```
  When you open the picker, the last tone you used in *this* app is preselected. Fresh apps fall back to the configured default.

### Cursor code-vs-prose heuristic

When frontmost app is `Cursor` (or `Code`, `VS Code`), classify the selection before choosing a tone.

**Heuristic:**
- Contains triple-backtick fence → **code**.
- Ratio of "code characters" (`{}()[];=<>`, any `/`, any `|`) to total non-whitespace chars > 15% → **code**.
- Starts with a comment marker (`//`, `#`, `/*`, `--`) → **code**.
- Contains two or more occurrences of common code keywords on distinct lines (`function|const|let|var|class|import|def|return|if|else|for|while|async|await|public|private|null|None|true|false`) → **code**.
- Otherwise → **prose**.

If **code** → apply Technical tone. If **prose** → apply Casual tone (Cursor chat register).

Heuristic runs in Python in ~1 ms. No accessibility calls.

### Config: editable app map

`~/.config/lingopulse/config.json` gets a new section (extending the one from `fixer-performance.md`):

```json
{
  "tone": {
    "default_tone": "Neutral",
    "app_map": {
      "Slack": "Casual",
      "Discord": "Casual",
      "Mail": "Professional",
      "Outlook": "Professional",
      "Cursor": "auto",
      "Code": "auto",
      "Visual Studio Code": "auto",
      "Messages": "Casual",
      "Notes": "Neutral",
      "Linear": "Professional"
    }
  }
}
```

- `"auto"` triggers the code-vs-prose heuristic.
- Unmapped apps fall back to `default_tone`.
- Shipped defaults include the common extras you're likely to use (Discord, Outlook, Messages, Notes, Linear) so you don't have to configure them.

## Open Questions (flag for /dev)

1. **Tone picker latency:** the picker opens a Raycast panel. If it takes >200ms to render, it defeats the <800ms total target. Raycast list views render quickly; measure during implementation.
2. **Heuristic tuning:** the 15% code-char threshold is a first guess. After a week of real use, log misclassifications (via the `history.jsonl` from `fixer-undo.md` if we extend it) and tune.
3. **Hebrew register signals:** the prompt's formality detection is designed for English. If the selection is partly Hebrew, Gemma's register judgment may be weaker. Not blocking; revisit after usage data.

## Tasks (for /dev)

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 1 | Rewrite Fixer system prompt per template in this doc | Backend / Prompt | Running the Fixer on a clearly-formal sentence inside Slack ("I wanted to flag a compliance concern…") preserves formality and punctuation. Running on a casual message in the same Slack session still lowercases and loosens appropriately. |
| 2 | Implement tone picker hotkey `Cmd+Opt+T` | Integration | Pressing `Cmd+Opt+T` on a selection opens a Raycast list with the 5 tones. Selecting one runs the refinement with that tone. Diff toast + undo buffer behave identically to `Cmd+Opt+E`. |
| 3 | Implement per-app tone memory | Backend | After picking "Professional" in Slack via `Cmd+Opt+T`, the next `Cmd+Opt+T` in Slack has "Professional" preselected. The next `Cmd+Opt+T` in Mail does NOT have "Professional" preselected — it uses Mail's config default or its own last-picked value. Stored in `~/.config/lingopulse/tone_overrides.json`. |
| 4 | Implement Cursor code-vs-prose heuristic | Backend | When frontmost app is Cursor and config maps it to `"auto"`, the Fixer classifies the selection per the heuristic and applies the correct tone. Manually tested with: a function body (→ technical), a chat message (→ casual), a code comment in English (→ decide: call it casual for now, log for later). |
| 5 | Ship extended config.json with app_map | Backend | On first run, `~/.config/lingopulse/config.json` contains the `tone` section with the default app map shown in this doc. Editing a tone mapping and restarting Raycast picks up the change. |
| 6 | Verify behavior for unmapped apps | QA | Opening a selection in an app not in the map (e.g., Firefox, Terminal, Figma) falls back to `default_tone`. Verified in at least 3 such apps. |
| 7 | Log tone-override misclassifications for tuning | QA / Telemetry | When the user presses `Cmd+Opt+T` within 60s of a `Cmd+Opt+E` refinement, `history.jsonl` records the pair (original auto-pick, user override). Enables after-the-fact tuning of the heuristic and app_map. |

## Hand-off

Tasks 1–7 go to `/dev`. Prompt change (Task 1) is isolated and can ship independently of the tone picker (Tasks 2–3) if we want to stage delivery.
