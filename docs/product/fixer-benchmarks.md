---
title: Fixer — Latency Benchmarks
status: STUB — fill after 1 week of real use
created: 2026-04-24
updated: 2026-04-24
---

# Fixer — Latency Benchmarks

Measured end-to-end wall-clock time from `Cmd+Opt+E` press to pasted refinement.

| Scenario | Cold (post-reboot) | Warm (<5 min since last use) | Warm-after-30-min-idle | Under memory pressure (Chrome + Cursor indexing + Docker) |
|----------|--------------------|------------------------------|------------------------|-----------------------------------------------------------|
| 10-word Slack message | TBD | TBD | TBD | TBD |
| 50-word paragraph | TBD | TBD | TBD | TBD |
| 200-word email draft | TBD | TBD | TBD | TBD |

## How to measure

```bash
# Terminal 1: tail the history log
tail -f ~/.config/lingopulse/history.jsonl

# Trigger a refinement with known-sized selection. Compare timestamps between your keypress and the refined entry.
```

Or add instrumentation inside `lingopulse/fixer.py` to log elapsed ms per stage (selection capture, inference, paste).

## Flag for revisit

If warm latency > 1.5s on short text, revisit quantization or model size. Gemma 4 E4B on an M4 Air should comfortably hit <800ms for short prompts.
