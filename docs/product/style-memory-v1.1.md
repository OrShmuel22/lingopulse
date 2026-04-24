---
title: Style Memory — v1.1 plan (DEFERRED)
status: DEFERRED — revisit when triggers below fire
created: 2026-04-24
updated: 2026-04-24
depends_on: [fixer-robustness.md]
---

# Style Memory — v1.1 plan

v1 ships without style memory in the prompt. The capture infrastructure is live: ⌘⌥M writes `{"mode":"style_example"}` entries to `history.jsonl`, and preview-mode refinements can log `user_edited` events.

## v1.1 plan

Add a new Raycast command `Compile Style Summary` (suggested hotkey: ⌘⌥⇧M):

1. Reads all `style_example=true` and `user_edited=true` entries from `history.jsonl`.
2. Runs an offline inference (non-blocking, single call) asking Gemma to produce an 80-token summary: "User prefers contractions on Slack, keeps 'deploy' over 'deployment', uses 'ramp' not 'scale up'..."
3. Stores result in `~/.config/lingopulse/style.json`.
4. The Fixer prompt builder appends the summary to every future Fixer request (~25 extra tokens, ~20–30ms latency hit).

## Triggers to revisit

Ship this when any of the below fire:

- [ ] 20+ `style_example=true` entries in history.jsonl (the user is consciously curating).
- [ ] Recurring pattern fights observed (e.g., Fixer keeps formalizing contractions you un-formalize).
- [ ] Preview-mode edit rate > 30% (user routinely overrides Fixer output).

## Implementation sketch

- New module: `lingopulse/style_memory.py` with `compile_summary()` and `load_summary()` functions.
- `lingopulse/prompts.py::build_fixer_prompt` optionally appends the summary if `style.json` exists.
- New Raycast script: `scripts/raycast/compile_style.py` — fullOutput mode, shows the compiled summary after writing it.
