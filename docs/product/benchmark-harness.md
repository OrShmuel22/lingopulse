---
title: Benchmark Harness (T15)
status: DECIDED
created: 2026-04-24
---

# Benchmark Harness

## Decision

A lightweight, stdlib-only benchmark harness (`lingopulse/benchmark.py`) that drives the live daemon over HTTP, evaluates responses against a fixed corpus (`benchmarks/scenarios.json`), and emits a JSON run file. No external dependencies; no LLM judging.

## Scoring

Three dimensions, weighted composite = `round(C*0.5 + Q*0.3 + L*0.2)`:

**Correctness (50%):** Pass/fail checks per scenario (token preservation, exact match for undo, `saved:true` for capture_style, keyword presence for refine, candidate count/language for dictionary). Score = passed_checks / total_checks × 100.

**Quality (30%):** Heuristics only, no LLM call. Casual tone: ≤25% of sentences start with a capital letter. Professional tone: all sentences end with `.`/`!`/`?`. Length stability: ratio in [0.7, 1.4] → 100, linearly down to 0 at [0.3, 3.0]. Dictionary: checks for `confidence` field (Hebrew path) and `register` field on all candidates.

**Latency (20%):** Piecewise linear — ≤500 ms → 100; 500–1500 ms → 100→70; 1500–3000 ms → 70→40; 3000–10000 ms → 40→0; >10 s → 0. Measured end-to-end from the Python `urllib.request` call.

## Alternatives considered

- **LLM-as-judge for quality:** Rejected. Adds latency, cost, and non-determinism; complicates reproducibility across model versions. Heuristics are weaker but stable.
- **pytest-based runner:** Rejected. The CLI compare/list/run structure needs to live outside pytest for use in CI scripts and manual ad-hoc runs. Unit tests for scoring functions still live in `tests/test_benchmark.py`.
- **External benchmark frameworks (e.g. lm-evaluation-harness):** Rejected. Overkill for a personal tool; would add heavy deps and a different mental model from the rest of the codebase.

## Corpus design

25 scenarios: 9 refine (5 Slack/Casual, 3 email/Professional, 1 long/Neutral), 2 code-preserve, 2 URL-preserve, 5 English dictionary, 5 Hebrew dictionary, 1 undo, 1 capture_style. Scenarios are the ground truth for future model comparisons — adding or changing them should be a deliberate, reviewed decision.
