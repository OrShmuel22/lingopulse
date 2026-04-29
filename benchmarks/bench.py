#!/usr/bin/env python3
"""LingoPulse LLM perf benchmark harness.

Hits the local Ollama HTTP API directly with the same prompts and options the
Swift app uses, so results reflect production behavior. No third-party deps:
runs against the system Python 3.

Usage:
  ./benchmarks/bench.py --models gemma3:1b-it-qat,gemma3:4b-it-qat \\
                        --modes fixer,dictionary \\
                        --warmup 2 --runs 3 \\
                        --out benchmarks/results/run-$(date +%Y%m%d-%H%M%S).json

Outputs:
  - JSON dump with every per-call sample (model, mode, prefill/decode counts,
    durations, tok/s)
  - Console summary with p50/p95/p99 latency and tok/s per (model, mode)
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

OLLAMA_HOST = "http://127.0.0.1:11434"
SAMPLES_PATH = Path(__file__).parent / "samples.json"

# Mirrors Prompts.swift fixerTemplate (stable-prefix variant). Keep in sync if
# you change the Swift template — drift makes the benchmark useless.
FIXER_TEMPLATE = """You fix English errors. You preserve everything else.

Rules:
1. Same number of sentences in output as input.
2. If input is correct, output = input. Do not rephrase clean text.
3. Keep code, URLs, names, technical terms, and Hebrew text verbatim.
4. Match the requested tone described in the context block below.

Examples:

Input:  who is responsible on staging?
Output: who is responsible for staging?

Input:  i have informations and feedbacks
Output: i have information and feedback

---
App: {app}
Tone: {tone_name} — {tone_description}

Input:  {message}
Output:"""

TONE_DESCRIPTIONS = {
    "Casual": "concise, friendly, lowercase allowed, minimal punctuation",
    "Neutral": "balanced clarity and grammar",
    "Technical": "precise, imperative, documentation-style, clear logic; preserve code identifiers and technical terms",
    "Professional": "polite, structured, standard business English",
    "Grammar-only": "fix grammar and spelling only; do not change tone or wording unless grammatically required",
}

DICT_EN_PROMPT = """You help a user find precise English words from a description.
Return a JSON object with a "candidates" array containing up to 3 word candidates.
For each candidate:
  "word": the English word or short phrase
  "example": one brief sentence showing the word in use
  "register": one of "casual", "neutral", "formal", "technical"
  "confidence": one of "high", "low"
Prefer words the user is likely looking for over archaic or obscure options.
Preserve existing English words from the query if they're already correct.

Query: {query}

Return only the JSON object. No preamble. No markdown fences."""

DICT_HE_PROMPT = """You help a native Hebrew speaker find precise English words.
The user has typed a description that may include Hebrew, English, or both.
Return a JSON object with a "candidates" array containing up to 3 word candidates.
For each:
  "word": the English word or short phrase
  "example": one brief sentence showing the word in use
  "register": one of "casual", "neutral", "formal", "technical"
  "confidence": one of "high", "low"

Rules:
- If you are uncertain about a translation, set confidence="low" and still include it.
- If you would be guessing, return fewer than 3 candidates rather than padding with uncertain options.
- Be conservative: prefer common, current words over archaic or rare ones.

Query: {query}

Return only the JSON object. No preamble. No markdown fences."""

DICT_SCHEMA = {
    "type": "object",
    "properties": {
        "candidates": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "word": {"type": "string"},
                    "example": {"type": "string"},
                    "register": {"type": "string", "enum": ["casual", "neutral", "formal", "technical"]},
                    "confidence": {"type": "string", "enum": ["high", "low"]},
                },
                "required": ["word"],
            },
        }
    },
    "required": ["candidates"],
}

HEBREW_RANGE = range(0x0590, 0x05FF + 1)


def has_hebrew(s: str) -> bool:
    return any(ord(c) in HEBREW_RANGE for c in s)


def build_fixer_prompt(sample: dict) -> str:
    return (
        FIXER_TEMPLATE.replace("{app}", sample["app"])
        .replace("{tone_name}", sample["tone"])
        .replace("{tone_description}", TONE_DESCRIPTIONS.get(sample["tone"], ""))
        .replace("{message}", sample["text"])
    )


def build_dict_prompt(sample: dict) -> str:
    template = DICT_HE_PROMPT if has_hebrew(sample["query"]) else DICT_EN_PROMPT
    return template.replace("{query}", sample["query"])


def call_ollama(model: str, prompt: str, options: dict, fmt=None, stream: bool = True, timeout: float = 120.0) -> dict:
    """Returns dict with keys: ttft_ms, total_ms, prompt_eval_count, eval_count,
    prompt_eval_duration_ms, eval_duration_ms, response_chars."""
    payload = {
        "model": model,
        "prompt": prompt,
        "keep_alive": "30m",
        "stream": stream,
        "options": options,
    }
    if fmt is not None:
        payload["format"] = fmt

    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{OLLAMA_HOST}/api/generate",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start = time.perf_counter()
    ttft = None
    accumulated = ""
    final = {}

    with urllib.request.urlopen(req, timeout=timeout) as resp:
        if not stream:
            data = json.loads(resp.read())
            total_ms = (time.perf_counter() - start) * 1000.0
            return {
                "ttft_ms": total_ms,
                "total_ms": total_ms,
                "prompt_eval_count": data.get("prompt_eval_count", 0),
                "eval_count": data.get("eval_count", 0),
                "prompt_eval_duration_ms": data.get("prompt_eval_duration", 0) / 1e6,
                "eval_duration_ms": data.get("eval_duration", 0) / 1e6,
                "response_chars": len(data.get("response", "")),
            }
        for raw in resp:
            line = raw.decode("utf-8").strip()
            if not line:
                continue
            chunk = json.loads(line)
            if ttft is None and chunk.get("response"):
                ttft = (time.perf_counter() - start) * 1000.0
            accumulated += chunk.get("response", "")
            if chunk.get("done"):
                final = chunk
                break

    total_ms = (time.perf_counter() - start) * 1000.0
    return {
        "ttft_ms": ttft if ttft is not None else total_ms,
        "total_ms": total_ms,
        "prompt_eval_count": final.get("prompt_eval_count", 0),
        "eval_count": final.get("eval_count", 0),
        "prompt_eval_duration_ms": final.get("prompt_eval_duration", 0) / 1e6,
        "eval_duration_ms": final.get("eval_duration", 0) / 1e6,
        "response_chars": len(accumulated),
    }


def warmup(model: str, n: int) -> None:
    for i in range(n):
        try:
            call_ollama(model, "warmup", {"num_predict": 4}, stream=False, timeout=60.0)
            print(f"  warmup {i+1}/{n} ok", flush=True)
        except Exception as e:
            print(f"  warmup {i+1}/{n} failed: {e}", file=sys.stderr, flush=True)


def fixer_options(text: str) -> dict:
    cap = min(2048, max(64, (len(text) * 5) // 3))
    return {
        "temperature": 0.1,
        "top_p": 0.9,
        "repeat_penalty": 1.0,
        "num_predict": cap,
        "stop": ["\nInput:", "\n\n", "\nOutput:"],
    }


def dict_options() -> dict:
    return {"num_predict": 384}


def run_mode(model: str, mode: str, samples: list, runs: int, strict_schema: bool) -> list:
    out = []
    for sample in samples:
        for run_idx in range(runs):
            if mode == "fixer":
                prompt = build_fixer_prompt(sample)
                opts = fixer_options(sample["text"])
                fmt = None
                key = sample["text"]
            elif mode == "dictionary":
                prompt = build_dict_prompt(sample)
                opts = dict_options()
                fmt = DICT_SCHEMA if strict_schema else "json"
                key = sample["query"]
            else:
                raise ValueError(f"unknown mode {mode}")

            try:
                m = call_ollama(model, prompt, opts, fmt=fmt, stream=True)
            except Exception as e:
                print(f"  ERROR {model}/{mode}: {e}", file=sys.stderr, flush=True)
                continue

            decode_tps = (m["eval_count"] / (m["eval_duration_ms"] / 1000.0)) if m["eval_duration_ms"] > 0 else 0.0
            prefill_tps = (m["prompt_eval_count"] / (m["prompt_eval_duration_ms"] / 1000.0)) if m["prompt_eval_duration_ms"] > 0 else 0.0

            row = {
                "model": model,
                "mode": mode,
                "run_idx": run_idx,
                "sample_key": key[:60],
                "prompt_chars": len(prompt),
                **m,
                "decode_tps": decode_tps,
                "prefill_tps": prefill_tps,
            }
            out.append(row)
            print(
                f"  {mode:10s} run={run_idx} ttft={m['ttft_ms']:7.0f}ms "
                f"total={m['total_ms']:7.0f}ms "
                f"prefill={m['prompt_eval_count']:4d}@{prefill_tps:6.1f}t/s "
                f"decode={m['eval_count']:4d}@{decode_tps:5.1f}t/s",
                flush=True,
            )
    return out


def percentile(xs: list, q: float) -> float:
    if not xs:
        return 0.0
    return statistics.quantiles(xs, n=100, method="inclusive")[int(q) - 1] if len(xs) >= 2 else xs[0]


def summarize(rows: list) -> None:
    by_key = {}
    for r in rows:
        by_key.setdefault((r["model"], r["mode"]), []).append(r)

    print("\n" + "=" * 100)
    print(f"{'MODEL':30s} {'MODE':12s} {'N':>3s} {'TTFT_p50':>10s} {'TTFT_p95':>10s} {'TOTAL_p50':>10s} {'TOTAL_p95':>10s} {'DECODE_t/s':>11s}")
    print("=" * 100)
    for (model, mode), rs in sorted(by_key.items()):
        ttfts = [r["ttft_ms"] for r in rs]
        totals = [r["total_ms"] for r in rs]
        decs = [r["decode_tps"] for r in rs if r["decode_tps"] > 0]
        print(
            f"{model:30s} {mode:12s} {len(rs):>3d} "
            f"{percentile(ttfts, 50):>10.0f} {percentile(ttfts, 95):>10.0f} "
            f"{percentile(totals, 50):>10.0f} {percentile(totals, 95):>10.0f} "
            f"{(statistics.median(decs) if decs else 0):>11.1f}"
        )
    print("=" * 100)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", required=True, help="comma-separated list, e.g. gemma3:1b-it-qat,qwen3:1.7b")
    parser.add_argument("--modes", default="fixer,dictionary")
    parser.add_argument("--warmup", type=int, default=2, help="warmup calls per model before measuring")
    parser.add_argument("--runs", type=int, default=3, help="repeat each sample N times")
    parser.add_argument("--out", type=str, default=None, help="path to write per-call JSON")
    parser.add_argument("--strict-schema", action="store_true", default=True)
    parser.add_argument("--no-strict-schema", dest="strict_schema", action="store_false")
    parser.add_argument("--samples", type=str, default=str(SAMPLES_PATH))
    args = parser.parse_args()

    samples = json.loads(Path(args.samples).read_text())
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    modes = [m.strip() for m in args.modes.split(",") if m.strip()]

    all_rows = []
    for model in models:
        print(f"\n--- {model} ---", flush=True)
        print(f"warmup x{args.warmup}", flush=True)
        warmup(model, args.warmup)
        for mode in modes:
            mode_samples = samples.get(mode, [])
            if not mode_samples:
                print(f"  no samples for mode={mode}, skipping", flush=True)
                continue
            all_rows.extend(run_mode(model, mode, mode_samples, args.runs, args.strict_schema))

    summarize(all_rows)

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps({
            "config": {
                "models": models,
                "modes": modes,
                "runs": args.runs,
                "warmup": args.warmup,
                "strict_schema": args.strict_schema,
            },
            "rows": all_rows,
        }, indent=2))
        print(f"\nwrote {len(all_rows)} rows to {out_path}", flush=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
