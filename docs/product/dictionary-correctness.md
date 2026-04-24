---
title: Dictionary — Correctness (v1, ship-simple)
status: DECIDED (v1) — revisit after real usage
created: 2026-04-24
updated: 2026-04-24
related_problems: [B6, B7]
---

# Dictionary — Correctness

> **Status:** DECIDED for v1 — ship simple, collect data, revisit if silent failures appear.
> **Created:** 2026-04-24 | **Updated:** 2026-04-24

## The Real Problem

The Dictionary is the scariest part of LingoPulse because its mistakes are invisible to the user. You type a Hebrew phrase or broken-English description, pick a confident-looking word, paste it into a professional message. You can't catch a wrong word because *not knowing the word is why you used the tool*. The Fixer's mistakes change text you wrote and can re-read. The Dictionary's mistakes insert a word you've never seen into context you wrote — you have no internal reference to detect it.

Two underlying causes:

1. **Model capacity.** gemma3:1b-it-qat is small. Hebrew→English and register judgment ("formal? archaic? current?") are weak points. It will confidently produce "rejuvenate" when you wanted "restart."
2. **Output format.** Bare-word output forces a non-native user to conjugate it correctly into their sentence — exactly the skill they're outsourcing.

## Scenarios

| Moment | What you need | What the spec delivers |
|--------|---------------|-----------------------|
| Query: "להפעיל מחדש שרת באופן מקצועי" | "Restart" or "cycle" with register markers | Bare list of 3 words, no register. May include "reboot," "refresh," "rejuvenate" — two wrong. |
| Broken-English: "when server clean memory again" | Right technical term | "Clear memory" / "flush cache" / "restart" — no signal which is right. |
| Sentence: "the server needs to be ___ed" | Correctly conjugated form | Bare "reboot." You guess "rebooten." |
| Professional email, query: "angry but polite" | Word with explicit register | Returns "vexed" (archaic-formal) with no register marker. |
| Hebrew query, model low confidence | A visible uncertainty signal | Always returns 3 confident-looking options. |

## Decision — v1

**Ship the spec as-is + one guardrail + one data-collection mechanism.**

Specifically:

1. **Model:** gemma3:1b-it-qat only. No second model for v1. Accept the correctness risk in exchange for simplicity (one model, one keep-alive schedule, ~2.5 GB memory total).
2. **UX:** Single input field, 3 word suggestions with 1-sentence examples — per spec.
3. **Hebrew uncertainty flag** (the one guardrail): when the query contains Hebrew characters, the prompt explicitly asks the model to mark uncertain candidates with `⚠️` and add a "low confidence" label next to the word. Best-effort — see Honest Limitations below.
4. **Query logging** (the data-collection): every Dictionary query + the 3 suggestions + which one the user picked is logged to `~/.config/lingopulse/history.jsonl`. No network calls — all local. Enables a later review of "did I keep using the tool for Hebrew queries? did I stop picking the first option?" to decide whether to invest in a bigger model.

### Why this, not B+C+D+E

Chose simplicity for v1 because:
- You have working history with gemma3:1b-it-qat from the Fixer. Starting there and measuring is faster than designing a two-model system speculatively.
- A 7B second model adds ~4.5 GB memory + its own keep-alive schedule + Ollama config complexity. If correctness is good enough with 4B + Hebrew flag, that complexity is waste.
- The data log lets us make the "bigger model" call based on real failure rates, not intuition.

## Honest Limitations (read before shipping)

The Hebrew uncertainty flag is best-effort, not reliable. gemma3:1b-it-qat has poor calibrated self-doubt — it will sometimes mark correct picks as ⚠️ and miss marking wrong ones. **Do not rely on the flag as a correctness guarantee.** Treat the Dictionary's output for Hebrew queries as "probably right, verify critical words."

In practice this means: for a Slack message to a friend, trust it. For a legal email, cross-reference the picked word against a dictionary or ask a native speaker.

If after two weeks of real use you find yourself distrusting the Dictionary (picking the 2nd or 3rd option often, or retrying queries), that's the signal to upgrade to the bigger model — revisit `Option B+C+D+E` from this doc's history.

## Details

### Query pipeline

1. User presses `Cmd+Opt+S`. Raycast input opens.
2. User types query. No extra field in v1.
3. Detect Hebrew characters (Unicode block `U+0590–U+05FF`) → select Hebrew-path prompt. Else → English-path prompt.
4. Send to gemma3:1b-it-qat via Ollama.
5. Parse structured response (see below).
6. Render Raycast list with flags.
7. User picks → clipboard → paste into active app.

### Prompts

**English / broken-English path:**
```
You help a user find precise English words from a description.
Return exactly 3 word candidates as a JSON array. For each candidate:
  "word": the English word or short phrase
  "example": one brief sentence showing the word in use
  "register": one of "casual", "neutral", "formal", "technical"
Prefer words the user is likely looking for over archaic or obscure options.
Preserve existing English words from the query if they're already correct.

Query: {QUERY}

Return only the JSON array. No preamble.
```

**Hebrew path:**
```
You help a native Hebrew speaker find precise English words.
The user has typed a description that may include Hebrew, English, or both.
Return up to 3 word candidates as a JSON array. For each:
  "word": the English word or short phrase
  "example": one brief sentence showing the word in use
  "register": one of "casual", "neutral", "formal", "technical"
  "confidence": one of "high", "low"

Rules:
- If you are uncertain about a translation, set confidence="low" and still include it.
- If you would be guessing, return fewer than 3 candidates rather than padding with uncertain options.
- Be conservative: prefer common, current words over archaic or rare ones.

Query: {QUERY}

Return only the JSON array. No preamble.
```

### Raycast list rendering

Each result row shows:
```
[word]                   [register]   [⚠️ low confidence if applicable]
  "example sentence"
```

Selecting a row → copy `word` to clipboard → paste into the app that was frontmost before Raycast opened.

### Query log format

One JSON line per query in `~/.config/lingopulse/history.jsonl`:

```json
{
  "timestamp": "2026-04-24T14:22:11+03:00",
  "mode": "dictionary",
  "query": "להפעיל מחדש שרת באופן מקצועי",
  "query_language": "hebrew",
  "candidates": [
    {"word": "restart", "register": "neutral", "confidence": "high"},
    {"word": "reinitialize", "register": "formal", "confidence": "high"},
    {"word": "reboot", "register": "neutral", "confidence": "low"}
  ],
  "picked": "restart",
  "picked_index": 0,
  "app": "Mail"
}
```

Useful signals when reviewing later:
- High rate of `picked_index >= 1` for Hebrew queries → Gemma often wrong in top pick → upgrade model.
- High rate of `picked=null` (user abandoned) → query needed refining → add sentence-context field.
- Specific queries with all `confidence=low` → model consistently weak on certain domains.

## Open Questions (flag for /dev)

1. **JSON parsing robustness:** gemma3:1b-it-qat sometimes wraps JSON in markdown fences, adds commentary, or breaks syntax. `/dev` should implement resilient parsing (strip fences, extract first JSON array, fall back to regex if parsing fails, show an error HUD rather than crash).
2. **Empty results:** if the model returns fewer than 3 candidates (Hebrew path allows this), UI should gracefully show however many it returned. Don't pad with fakes.
3. **Paste target:** spec says "pastes it into the active app." Resolve the same way as the Fixer — the app that was frontmost before Raycast took focus. Needs the same text-injection fallback matrix as `fixer-undo.md` Task 9.

## Revisit Criteria (when to invest in a bigger model)

Revisit this decision after 2 weeks of real use if any of these are true:

- You're picking `picked_index >= 1` more than 30% of the time for Hebrew queries (the top pick is often wrong).
- You're abandoning queries (picking nothing) more than 20% of the time.
- You've caught yourself pasting a wrong word from the Dictionary more than twice.

If revisiting: open this doc, promote the `Option B+C+D+E` section from history to a new decision, and implement Qwen 7B (or re-benchmark current best multilingual ~7–8B) as the Dictionary model.

## Tasks (for /dev)

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 1 | Implement Hebrew detection in query preprocessor | Backend | A query containing any codepoint in U+0590–U+05FF routes to the Hebrew prompt path. A query with no Hebrew codepoints routes to the English path. Verified with 5 English, 5 Hebrew, 3 mixed queries. |
| 2 | Ship the two Dictionary prompts | Backend / Prompt | Running the English prompt on "the word for restarting a server but professionally" returns a JSON array of 3 candidates with word/example/register fields. Running the Hebrew prompt on "להפעיל מחדש שרת" returns up to 3 candidates with the `confidence` field present. |
| 3 | Implement resilient JSON parsing with fallbacks | Backend | Given output wrapped in markdown fences, preceded by commentary, or containing trailing text, the parser extracts the JSON array cleanly. If parsing fails after all fallbacks, an HUD shows "Dictionary couldn't parse the response — try rephrasing" and the flow exits cleanly. |
| 4 | Render Raycast list with register + confidence markers | UX | Each row shows the word, its register tag, the example sentence, and a `⚠️ low confidence` indicator when `confidence=="low"`. Rows with `high` confidence show no ⚠️. |
| 5 | Implement paste-into-previous-app flow | Integration | Selecting a candidate copies the `word` to the clipboard and pastes it at the cursor of the app that was frontmost before Raycast opened. Works in Slack, Mail, Cursor; uses the same text-injection fallback as the Fixer. |
| 6 | Implement query logging to history.jsonl | Backend | Every Dictionary query appends one JSON line to `~/.config/lingopulse/history.jsonl` with the schema above. File is append-only, grows unbounded (fine at this scale — <1 KB per query, <365 KB/year at heavy use). |
| 7 | Document "Honest Limitations" in first-run message | UX | On first-ever invocation of the Dictionary, a one-time Raycast HUD shows: "Heads up: Hebrew queries may return uncertain translations, marked with ⚠️. For important messages, verify critical words." Dismissible; never shown again. |
| 8 | QA: 20-query Hebrew correctness baseline | QA | `docs/product/dictionary-baseline.md` exists listing 20 Hebrew queries, the top candidate gemma3:1b-it-qat returned, whether a native Hebrew speaker judges it correct. Baseline informs the "revisit criteria" threshold. |

## Hand-off

Tasks 1–8 go to `/dev`. Ship this simple version. The logging (Task 6) and baseline (Task 8) are specifically for the "revisit criteria" — they exist so the decision to upgrade is data-driven, not anxiety-driven.

## v2 NOTE (2026-04-24)

Dictionary candidates are now individually clickable in the v2 Raycast Extension (real row-selection via `<List>`). The v1 limitation "first candidate auto-copies; 2nd/3rd require manual highlight" is **resolved**. `picked_index` in history.jsonl now reflects the user's actual pick.
