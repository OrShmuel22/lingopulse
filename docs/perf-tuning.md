# LingoPulse LLM perf tuning

Living doc. Update with measurement results, not vibes.

## What's already wired (code)

| Lever | Where | Status |
|---|---|---|
| Stable-prefix prompt for KV cache reuse | `Prompts.swift` `fixerTemplate` | ✅ shipped |
| `num_predict` cap on Fixer (`min(2048, max(64, len*5/3))`) | `Fixer.swift` | ✅ shipped |
| `num_predict` cap on Dictionary (`384`) | `DictionaryCommand.swift` | ✅ shipped |
| Streaming Fixer infra (`generateStream` + `onToken`) | `OllamaService.swift`, `Fixer.swift` | ✅ infra; UI still calls non-stream path. Wire `onToken` from the active typing/preview surface to claim the TTFT win. |
| Active-hours-aware `keep_alive` (model unloads outside 08:00–22:00) | `KeepaliveOrchestrator.swift` | ✅ shipped |
| Dictionary `format` toggle (strict schema vs `format:"json"`) | `DictionaryCommand.swift` + Settings → Models | ✅ shipped, default = strict |
| Mismatched-model warning (Refine vs Dictionary) | `ModelsPromptsTab.swift` | ✅ shipped |

## What needs an env-var change (Ollama daemon)

Run once:

```sh
./scripts/setup_ollama_env.sh --apply
# then quit & relaunch the Ollama menu-bar app
```

This sets:

- `OLLAMA_FLASH_ATTENTION=1` — official rec for "significantly reduce memory as context grows"
- `OLLAMA_KV_CACHE_TYPE=q8_0` — ~50% KV memory drop with very small precision loss
- `OLLAMA_NUM_PARALLEL=2` — Refine and Dictionary can run concurrently

Persist across reboot per the script's instructions (zshrc export OR launchd plist).

## Benchmark loop

`benchmarks/bench.py` is dependency-free. Mirrors the production prompts (Fixer template + Dictionary EN/HE prompts + JSON schema) and records `ttft_ms`, `total_ms`, `prompt_eval_count`, `eval_count`, prefill/decode tok/s.

Baseline:

```sh
python3 benchmarks/bench.py \
  --models gemma3:1b-it-qat \
  --modes fixer,dictionary \
  --warmup 2 --runs 3 \
  --out benchmarks/results/baseline.json
```

After enabling env vars + restarting Ollama:

```sh
python3 benchmarks/bench.py \
  --models gemma3:1b-it-qat \
  --modes fixer,dictionary \
  --warmup 2 --runs 3 \
  --out benchmarks/results/post-env.json
```

Compare `decode_t/s` and `ttft_p50` between runs.

## Model bake-off (qwen3 vs gemma3)

Pull qwen3 first:

```sh
ollama pull qwen3:1.7b
```

Run head-to-head:

```sh
python3 benchmarks/bench.py \
  --models gemma3:1b-it-qat,gemma3:4b-it-qat,qwen3:1.7b \
  --modes fixer,dictionary \
  --warmup 2 --runs 3 \
  --out benchmarks/results/model-bakeoff.json
```

Decision rule per the global memory note: **never commit on a smoke test**. Run all
samples × 3 repeats minimum. Quality check is manual diff or LLM-judge — speed alone
is insufficient.

## JSON schema A/B (Dictionary)

Strict schema (default) uses grammar-constrained sampling — guaranteed valid JSON,
~15–30% slower per published numbers. The tolerant path uses `format:"json"` plus the
existing markdown-fence stripper.

```sh
# strict
python3 benchmarks/bench.py --models gemma3:1b-it-qat --modes dictionary --runs 5 \
  --strict-schema --out benchmarks/results/dict-strict.json

# tolerant
python3 benchmarks/bench.py --models gemma3:1b-it-qat --modes dictionary --runs 5 \
  --no-strict-schema --out benchmarks/results/dict-tolerant.json
```

In the tolerant run, also count parse failures (rows where `Dictionary.parseResponse`
would have returned `[]` — the bench dumps `response_chars`, but a richer parse-success
audit needs the Swift parser; easiest is to feed the raw responses through a small
extracted parser script, or eyeball a sample). Switch the default if parse-failure
rate < 2% AND latency win > 100 ms.

## MLX backend (Apple Silicon)

Ollama 0.19+ ships an MLX backend that gives ~1.6× prefill / ~2× decode on Apple
Silicon (per Ollama blog, March 2026). Enable with:

```sh
export OLLAMA_USE_MLX=1
ollama serve   # or restart the menu-bar app from a shell that has the var set
```

**Caveat (as of 2026-04):** the preview accelerates only `Qwen3.5-35B-A3B`. Gemma3
family is not MLX-accelerated yet — setting the var with gemma3 silently falls back to
the llama.cpp path. Track support at https://github.com/ollama/ollama/releases. When a
gemma3 (or qwen3:1.7b) MLX build lands, re-run `bench.py` with `OLLAMA_USE_MLX=1` set.

If the qwen3.5 path becomes viable for Fixer/Dictionary at smaller-param sizes once
MLX expands, that's the moment to seriously consider switching defaults.
