---
title: Pipeline Architecture (v3) — purpose-built components, not generic LLM
status: DECIDED — ready for /dev (Phase 1: Fixer)
created: 2026-04-24
updated: 2026-04-24
supersedes_single_llm_approach_in: [fixer-undo.md, fixer-tone-context.md, dictionary-correctness.md]
---

# Pipeline Architecture (v3)

> **Status:** DECIDED — Phase 1 (Fixer pipeline) ready for `/dev`. Phase 2 (Dictionary retrieval) queued.
> **Created:** 2026-04-24 | **Updated:** 2026-04-24

## The Real Problem

v2 (gemma3:1b-it-qat baseline, composite 91.5 on 31 scenarios) has measurable, structural weaknesses that prompt tuning can only patch — not solve:

| Measured failure | Root cause |
|-----------------|------------|
| Homophones (your/you're, there/their) — comp 60 | 1B models can't reliably disambiguate grammatical role; near the floor for syntactic parsing |
| Dictionary returns 1-of-3 candidates — comp 73 | Small models satisfice on format unless structurally constrained; prompt instruction "return 3" gets ignored |
| Slack casual tone over-capitalizes — qual 50 on 5 scenarios | Instruction-tuned models RLHF'd toward standard capitalization; pretraining prior dominates for small models |
| Hebrew refine drops English technical terms — comp 83 | 1B has shallow cross-lingual alignment; regenerates "normalized" all-Hebrew output |
| Long-input 6.9s latency (300 words) | Pure O(N) cost of generative decoding |

These are **three different problems** (grammar correction / style transfer / concept-to-word search) bolted onto one generalist LLM. Real grammar tools (Grammarly, Google Docs, LanguageTool) use pipelines of specialized components. v3 does the same.

## Scenarios (from the v2 benchmark)

| Moment | What the user needs | What v2 delivers |
|--------|-------------------|------------------|
| Types "your right, there going to there office" in Slack, ⌘⌥E | "You're right, they're going to their office" | "Your right, there are going to be there office" — 3 of 4 homophones unfixed |
| Types Slack message all lowercase, ⌘⌥E | Output stays lowercase (Slack vibe) | Output starts "Hey, can you please..." — over-capitalized |
| Hebrew query "להפעיל מחדש שרת באופן מקצועי" via ⌘⌥S | 3 candidates: restart, reinitialize, cycle | 1 candidate: restart. No alternatives. |
| Hebrew Slack message with English word `deployment`, ⌘⌥E | Refined Hebrew with `deployment` preserved | Hebrew refined but `deployment` dropped; invented nonsense word `הדיפול` |
| 300-word incident summary, ⌘⌥E | Refine in ~2s | 7s wait |

## Decision

**Replace single-LLM design with a pipeline of purpose-built components, staged in two phases.**

### Architecture (v3)

**Fixer pipeline (Phase 1):**
```
Selection
  → GEC model                  (pszemraj/grammar-synthesis-small, ~250MB, T5-small)
     ↳ fixes homophones, typos, punctuation, subject-verb agreement deterministically
  → Tone classifier            (rule-based, <10ms)
     ↳ decides if register needs adjusting based on app + input style
  → [OPTIONAL] LLM              (gemma3:1b-it-qat) — ONLY for tone shift
     ↳ called only when tone change required; most refines skip this
  → Output
```

**Dictionary pipeline (Phase 2, queued):**
```
Query (EN or HE)
  → Multilingual embedder      (paraphrase-multilingual-MiniLM-L12-v2, ~440MB)
  → Cosine search              (over precomputed vocabulary DB, ~20K words + register tags, ~40MB)
  → Top-20 candidates
  → Re-ranker                  (small LLM or cross-encoder)
  → 3 final candidates with examples
```

### Phases

| Phase | Scope | Ships | Status |
|-------|-------|-------|--------|
| 1 | Fixer pipeline + tone classifier + demoted LLM | This cycle | Ready for `/dev` |
| 2 | Dictionary retrieval + embedding + ranker | Next cycle | Queued, spec below |

Reason for staging: Fixer is the 20–50×/day action; Dictionary is 3–5×/day. Ship the bigger lever first, benchmark, learn, then ship Dictionary.

### Runtime choice (locked)

- **`transformers` + PyTorch MPS backend** for both GEC and embedder.
- Installed into existing `.venv` (honors no-host-install rule).
- MPS uses Apple Silicon GPU via PyTorch — 3–5× slower than native MLX but still <200ms for our model sizes, and dramatically simpler than MLX conversion for T5 models.
- Can revisit MLX later if perf becomes limiting (unlikely for 250MB models).

### Model choices (locked)

- **GEC:** `pszemraj/grammar-synthesis-small` (~250MB, ~60M params, T5-small). Purpose-built for grammatical error correction, trained on C4-200M GEC corpus. Published 95%+ F0.5 on homophones.
- **Embedder (Phase 2):** `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (~440MB). Multilingual including Hebrew. 384-dim embeddings, fast cosine search.
- **Re-ranker (Phase 2):** keep `gemma3:1b-it-qat` for generation of examples + final ranking of top-20 to top-3.

## Details — Phase 1 (Fixer)

### New modules

- `lingopulse/gec.py` — loads the GEC model once (module-level), exposes `correct(text: str) -> str`. PyTorch/MPS runtime. Warmup on import to avoid first-call latency.
- `lingopulse/tone.py` — the rule-based tone classifier. Given `(input_text, app)`, returns `needs_tone_shift: bool` and `target_tone: str`.

### Fixer flow (updated `lingopulse/fixer.py::refine()`)

1. Capture selection + app (existing).
2. `protect()` URLs + code (existing).
3. **NEW:** `gec.correct(redacted)` — grammar + homophones + typos fixed.
4. **NEW:** `tone.needs_shift(selection, app, tone_override)` — check if register change needed.
5. **Conditional:** if tone shift needed OR explicit `tone_override`, call LLM for style transfer. Otherwise, skip.
6. `restore()` tokens (existing).
7. Ring buffer append, paste, toast (existing).

Expected behavior:
- Short clean Slack message with typos: GEC fixes typos → no tone shift needed → output ≈ 150ms total.
- Formal email with bad grammar: GEC fixes → no tone shift (already formal) → output ≈ 200ms.
- "Make this formal" override: GEC fixes → LLM style transfer → output ≈ 2s.
- Hebrew text: GEC skipped (model is English-only for v3; Hebrew grammar is user's native language, assumed clean) → direct passthrough → ≈ 50ms.

### Tone classifier rules (v1)

```
target_tone = config.tone.app_map[app] or config.tone.default
current_register = heuristic_detect(text)
  - ratio of lowercase sentence starts > 50%   → "casual"
  - all sentences end with . ! ?               → "formal"
  - mean sentence length > 20 words            → "formal"
  - else                                        → "neutral"
needs_shift = current_register != target_tone (with Casual<->Neutral considered equivalent)
```

This is a heuristic, not ML. ~20 lines of code, deterministic, fast.

### Fallback strategy

- **GEC fails to load** (model not downloaded, torch not present): fall back to current LLM-only flow. Log error. Daemon remains healthy.
- **GEC raises at inference** (OOM, timeout): fall back to LLM. Log.
- **MPS not available** (e.g., running on non-Apple hardware): use CPU backend. ~2× slower but still works.

### Model download strategy

- First daemon startup after install: auto-download GEC model from HuggingFace to `~/.cache/huggingface/hub/`. ~250MB, one-time, ~30–60s on typical connection.
- `install.sh` pre-downloads by running a dummy GEC call during install. User never sees a delay on first hotkey press.

### Config additions

```json
"pipeline": {
  "gec_enabled": true,
  "gec_model": "pszemraj/grammar-synthesis-small",
  "gec_max_length": 512,
  "tone_classifier_enabled": true
},
"fallback": {
  "llm_only_if_gec_fails": true
}
```

### What stays identical

- Daemon HTTP architecture, endpoints
- Raycast extension
- Ring buffer, history, clipboard, protection, apps, hud modules
- LaunchAgents (warmup, keepalive, daemon)
- Config.json as source of truth
- Benchmark harness (will quantify the upgrade)
- gemma3:1b-it-qat (demoted from "primary" to "tone shift only")

### What gets demoted / retired

- Heavy Fixer prompt in `lingopulse/prompts.py` — no longer primary. Kept for when LLM is called for tone shift.
- The homophone-correction prompt instructions I would have added (tier-1 patch) — **not needed** now that GEC handles it natively.

## Details — Phase 2 (Dictionary, queued)

Not implementing this cycle. Sketched for continuity:

1. One-time vocabulary build (`scripts/build_wordlist.py`):
   - Pull WordNet via `nltk` (20K+ common English words)
   - Assign register tags via an LLM-generated one-time classification (runs once offline, not per-query)
   - Compute MiniLM embeddings → `data/embeddings.npy` + `data/wordlist.json`
2. Daemon `/dictionary` handler rewrite:
   - Embed query with same MiniLM → cosine search top-20 → LLM re-rank to 3 → generate examples for the 3 winners.
3. Benchmark compare → expected gains on `dict-en-*`, `dict-he-*`, and especially `dict-3-candidates-required-01` (50 → 100).

## Open Questions (flag for /dev)

1. **GEC handling of code/URLs**: does `grammar-synthesis-small` respect our placeholder tokens `⟨⟨LP:xxxxxx⟩⟩`? Test during implementation; if it mangles them, add post-pass to restore from placeholder map.
2. **GEC with Hebrew**: model is English-only. Phase 1 decision: skip GEC entirely if input has Hebrew characters. Passthrough + optional LLM call if tone override requested. Document this behavior clearly.
3. **Memory footprint with MPS**: GEC (250MB) + embedder (440MB, Phase 2) + gemma3:1b-it-qat (1.7GB) = ~2.4GB on GPU. Fits M4 Air 24GB comfortably. Verify during benchmarks.
4. **GEC warmup timing on MPS**: first inference after model load can be 1–2s due to MPS graph compilation. Warm during daemon startup (blocking), not on first user call.
5. **Benchmark comparability**: v3 results will go in the same benchmark format. The 31-scenario corpus doesn't need to change — the pipeline should score higher on the same tests. If new failure modes emerge, add scenarios in v3.1.

## Tasks for /dev (Phase 1 only)

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 1 | Add `transformers` + `torch` to requirements, install in .venv, verify MPS backend works | Infrastructure | `.venv/bin/python -c "import torch; print(torch.backends.mps.is_available())"` returns `True`. `.venv/bin/python -c "from transformers import pipeline"` loads without error. |
| 2 | Implement `lingopulse/gec.py` with warmup, `correct()` function, MPS backend, placeholder-safe | Backend | Given input with typos and homophones ("your right, should of went"), `gec.correct()` returns corrected text ("You're right, should have gone") in <500ms. Given input with URLs/code placeholders (`⟨⟨LP:abc⟩⟩`), placeholders survive byte-identical. |
| 3 | Implement `lingopulse/tone.py` with rule-based classifier | Backend | `tone.needs_shift("hey u around?", app="Slack", target="Casual")` returns `False`. Same input with `target="Professional"` returns `True`. All branches have unit tests. |
| 4 | Refactor `lingopulse/fixer.py::refine()` to use GEC → tone check → optional LLM pipeline | Backend | Benchmark scenario `refine-homophone-01` composite goes from 60 → 90+. `refine-slack-01..05` quality goes from 50 → 90+ (no more forced capitalization). Scenario `refine-hebrew-stays-hebrew-01` unchanged or improved (GEC skipped, LLM only called if tone override). |
| 5 | Add GEC model preload to `install.sh` | Infrastructure | First run of `./scripts/install.sh` downloads the GEC model. Re-running doesn't re-download. Daemon startup completes GEC warmup before reporting `model_loaded=true` on `/status`. |
| 6 | Add config knobs: `pipeline.gec_enabled`, `pipeline.gec_model`, `pipeline.tone_classifier_enabled` | Backend | Setting `pipeline.gec_enabled=false` in config.json causes refine to use the v2 LLM-only flow. Backward-compatible with existing config.json. |
| 7 | Update unit tests for `lingopulse/fixer.py`: new pipeline paths (GEC only, GEC+LLM, fallback) | Tests | `tests/test_fixer.py` covers: GEC-only path (no tone shift), GEC+LLM path (tone override), GEC failure → LLM fallback. All 166 existing tests still pass. |
| 8 | Run benchmark on the new pipeline; run `compare` against the gemma3:1b-it-qat baseline | QA | `benchmarks/run-<timestamp>_pipeline-v3-phase1.json` exists. `python -m lingopulse.benchmark compare` shows composite ≥95 (vs 91.5 baseline) with explicit improvement on homophone, slack, long-content scenarios. |
| 9 | Update `README.md`: architecture section describes pipeline, new model requirements, new config | Docs | README accurately reflects v3. Old "single LLM" language removed. Install steps include GEC model download. |
| 10 | Update memory file `project_model_landscape.md` with Phase 1 results | Docs | Post-benchmark composite and latency numbers added. Any new findings documented. |

## Hand-off

- Tasks 1–10 go to `/dev` for Phase 1.
- Phase 2 (Dictionary retrieval) is documented above but **not** in this task list — open a fresh product doc + dev cycle after Phase 1 ships and you've lived with the Fixer pipeline for a few days.
- If Phase 1 benchmark shows <93 composite (below the expected 95+), do NOT ship — investigate first. The v2 baseline 91.5 is still the floor; anything below that is a regression.
