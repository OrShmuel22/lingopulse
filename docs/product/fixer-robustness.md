---
title: Fixer — Robustness Batch (Clipboard, Code/URL, Style Memory)
status: DECIDED
created: 2026-04-24
updated: 2026-04-24
related_problems: [B3, B5, M1, F7]
---

# Fixer — Robustness Batch

> **Status:** DECIDED — ready for `/dev`
> **Created:** 2026-04-24 | **Updated:** 2026-04-24

Three smaller problems batched into one doc because the decisions are small and the implementations are related (all sit in the Fixer's copy→infer→paste pipeline).

---

## B3 — Clipboard save/restore

### The Real Problem

You have a URL on your clipboard. You hit `Cmd+Opt+E` on a Slack message. The Fixer copies your selection (overwriting the URL), runs inference, pastes the refined text (overwriting the clipboard a second time). Your URL is gone. The Dictionary has the same bug: picking a word replaces whatever was on the clipboard.

### Decision

**Text-only save/restore wrapper** around every copy→infer→paste cycle.

```python
saved = subprocess.check_output(['pbpaste']).decode('utf-8', errors='replace')
# ... selection copy / inference / paste dance ...
subprocess.run(['pbcopy'], input=saved.encode('utf-8'))
```

### Trade-off accepted

Non-text clipboards (images, files) are still clobbered. In practice almost everything a power user keeps on the clipboard is text (URLs, commands, quotes). Full `NSPasteboard` preservation via `pyobjc` is overkill for a personal tool; the 50 extra lines and one new dependency aren't worth the <5% edge case.

If this ever bites you in practice, upgrade to the full `NSPasteboard` path — it's a localized change behind the same wrapper.

---

## B5 — Code / URL / markdown passthrough

### The Real Problem

Selection contains `` `handleClick()` `` or `https://github.com/...`. The model "improves" them: `handleClick` → "the handleClick function," URL gets a trailing slash stripped, backticks reformatted. The P3 tone prompt tells the model to preserve these verbatim, but that's a promise, not a guarantee.

### Decision

**Two-layer defense: regex protection for unambiguous cases + prompt for the rest.**

1. **Pre-extraction layer (before inference):**
   - Regex-match URLs: `https?://\S+`
   - Regex-match triple-backtick fenced code blocks: `` ```[\s\S]*?``` ``
   - Regex-match inline backtick pairs: `` `[^`]+` ``
   - Replace each match with a placeholder: `[[PROTECT_0]]`, `[[PROTECT_1]]`, …
   - Send redacted text to model.
   - In the model's output, replace placeholders with original strings (verbatim).
2. **Prompt layer (already in place from P3):** instruction to preserve technical terms, code identifiers, and proper nouns verbatim.

### Why this split

- URLs and fenced code are unambiguous (regex-safe). Protecting them is cheap and bulletproof.
- Inline identifiers like `camelCaseVar` and `snake_case_func` are ambiguous — a too-aggressive regex would match `JavaScript` or `GitHub`, which are normal English words the model should be allowed to lowercase if appropriate. Leave those to the prompt.
- If the prompt layer fails on inline identifiers in practice, we can tighten the regex later without user impact.

### Edge cases

- Placeholder collision: if the user's text literally contains `[[PROTECT_0]]`, we'd corrupt it on restore. Probability: astronomically low. Mitigate: use a less-collidable token like `⟨⟨LP:a1b2⟩⟩` with a random per-request suffix.
- Model strips or rewrites the placeholder: rare but possible on Gemma 4B. Mitigate: validate that every placeholder appears exactly once in the output before restoring. If missing, fall back to showing the raw output with an HUD warning rather than corrupting.

---

## M1 + F7 — Style memory

### The Real Problem

The spec says "append last 5–10 manual corrections to the prompt." Two issues:

- **M1 (capture):** the spec doesn't say *how* manual corrections are detected. Without a capture mechanism, style memory is vaporware.
- **F7 (cost):** even if captured, appending 5–10 full corrections adds ~250–500 tokens per request → ~100–200 ms latency on Gemma 4B Q4. Directly fights the <800 ms performance goal locked in `fixer-performance.md`.

### Decision

**Defer style memory to v1.1. Ship capture infrastructure in v1 only.**

Specifically:

1. **v1 includes:** `Cmd+Opt+M` — a manual capture hotkey that saves the current selection as a "style example" (flagged in `history.jsonl`). No prompt integration yet. Explicit curation, not automatic detection.
2. **v1 also captures implicitly:** edits to the Fixer's output within the preview-mode flow (`Cmd+Opt+Shift+E` from `fixer-undo.md`) are automatically logged as style signals — the diff between the model's output and what you typed instead is already visible in that flow.
3. **v1 does NOT include:** prompt append of style examples. Zero latency cost.
4. **v1.1 will add:** a `Cmd+Opt+Shift+M` command ("compile style") that reads all `style_example=true` entries and preview-mode overrides from `history.jsonl`, runs an offline inference pass to produce an ~80-token style summary paragraph, and stores it in `~/.config/lingopulse/style.json`. From that point on, the summary is appended to every Fixer prompt. Token cost: ~80 tokens per request = ~20–30 ms latency. Acceptable.

### Why defer

- You don't know yet whether the Fixer's outputs will drift from your voice. Building a personalization system for a hypothetical problem is waste.
- The capture infrastructure costs little (one hotkey, one log field). You accumulate data from day one.
- When the drift is real enough to bother you, you run one command and v1.1 is live.

### Triggers to revisit

After 2 weeks of use, revisit if any apply:
- You have 20+ `style_example=true` entries in `history.jsonl` (you consciously want the feature).
- You notice recurring pattern fights with the Fixer (e.g., it keeps formalizing your contractions).
- Preview-mode edit rate is high (>30% of `Cmd+Opt+Shift+E` uses result in you editing the output).

At that point, promote the v1.1 plan from this doc and implement the compile-style command.

---

## Tasks (for /dev)

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 1 | Clipboard save/restore wrapper (text-only) | Backend | Before running the Fixer with a URL on the clipboard, then after, `pbpaste` returns the same URL. Verified for Fixer, Dictionary pick, and preview-mode accept paths. |
| 2 | URL + fenced-code + inline-backtick regex protection layer | Backend | Running the Fixer on "check out https://github.com/anthropics/claude-code — it's cool" replaces only the prose; the URL is byte-identical in the output. Fenced code blocks and `inline` backtick pairs pass through unmodified. |
| 3 | Placeholder collision & strip safety | Backend | If the model fails to preserve a placeholder, the user sees an HUD "Refinement returned unexpected output — original preserved" and the original text is NOT replaced. Verified by stubbing the model to drop a placeholder. |
| 4 | `Cmd+Opt+M` style-example capture hotkey | Integration | Pressing `Cmd+Opt+M` on a selection writes one line to `history.jsonl` with shape `{"mode":"style_example","text":"...","app":"Slack","timestamp":"..."}` and shows a brief HUD "Saved as style example." No effect on Fixer behavior. |
| 5 | Preview-mode edit-capture logging | Integration | When you use `Cmd+Opt+Shift+E` and then edit the refined text before accepting, the log entry for that refinement includes `user_edited: true` and stores the final-accepted text alongside the model's original output. Passive data collection. |
| 6 | Add style-memory revisit doc stub | Docs | `docs/product/style-memory-v1.1.md` exists as a stub with the v1.1 plan copied from this doc, status: DEFERRED, and the "triggers to revisit" checklist. Makes the next decision a 1-step rather than a re-research. |

## Hand-off

Tasks 1–6 to `/dev`. Smallest and cleanest batch of the four Fixer docs.

## v2 NOTE (2026-04-24)

Clipboard save/restore now lives inside the daemon's /refine handler. Behavior unchanged — text-only preservation still applies.
