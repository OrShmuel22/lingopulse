"""
Benchmark harness for LingoPulse.

Usage:
    python -m lingopulse.benchmark run [--out DIR]
    python -m lingopulse.benchmark compare [file_a] [file_b]
    python -m lingopulse.benchmark list
"""

import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

_REPO_ROOT = pathlib.Path(__file__).parent.parent
_SCENARIOS_PATH = _REPO_ROOT / "benchmarks" / "scenarios.json"
_BASE_URL = "http://127.0.0.1:17823"

# ---------------------------------------------------------------------------
# Scoring functions (pure, no I/O — easy to unit-test)
# ---------------------------------------------------------------------------


def _latency_score(elapsed_ms: float) -> float:
    """Piecewise linear latency score (0-100)."""
    if elapsed_ms <= 500:
        return 100.0
    if elapsed_ms <= 1500:
        return 100.0 - (elapsed_ms - 500) / 1000 * 30.0
    if elapsed_ms <= 3000:
        return 70.0 - (elapsed_ms - 1500) / 1500 * 30.0
    if elapsed_ms <= 10000:
        return 40.0 - (elapsed_ms - 3000) / 7000 * 40.0
    return 0.0


def _correctness_score(checks: dict) -> float:
    """Pass/fail checks rolled up as (passed/total * 100)."""
    if not checks:
        return 100.0
    total = len(checks)
    passed = sum(1 for v in checks.values() if v)
    return passed / total * 100.0


def _quality_score_casual(text: str) -> float:
    """Casual tone heuristic: <=25% sentences start with a capital letter."""
    if not text.strip():
        return 0.0
    import re
    sentences = [s.strip() for s in re.split(r"[.!?]", text) if s.strip()]
    if not sentences:
        return 100.0
    cap_count = sum(1 for s in sentences if s and s[0].isupper())
    ratio = cap_count / len(sentences)
    if ratio <= 0.25:
        return 100.0
    # linearly down to 0 at ratio=1.0
    return max(0.0, 100.0 * (1.0 - ratio) / 0.75)


def _quality_score_professional(text: str) -> float:
    """Professional tone heuristic: all sentences end with punctuation."""
    if not text.strip():
        return 0.0
    import re
    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s.strip()]
    if not sentences:
        return 100.0
    properly_ended = sum(1 for s in sentences if s and s[-1] in ".!?")
    return properly_ended / len(sentences) * 100.0


def _length_stability_score(orig_words: int, refined_words: int) -> float:
    """Score how stable the length is after refinement."""
    if orig_words == 0:
        return 100.0 if refined_words == 0 else 0.0
    ratio = refined_words / orig_words
    if 0.7 <= ratio <= 1.4:
        return 100.0
    # below 0.7: linear from 100 at 0.7 to 0 at 0.3
    if ratio < 0.7:
        if ratio <= 0.3:
            return 0.0
        return (ratio - 0.3) / (0.7 - 0.3) * 100.0
    # above 1.4: linear from 100 at 1.4 to 0 at 3.0
    if ratio >= 3.0:
        return 0.0
    return (3.0 - ratio) / (3.0 - 1.4) * 100.0


def _composite(correctness: float, quality: float, latency: float) -> int:
    """Weighted composite score. Returns int."""
    return round(correctness * 0.5 + quality * 0.3 + latency * 0.2)


# ---------------------------------------------------------------------------
# Evaluation helpers
# ---------------------------------------------------------------------------


def _word_count(text: str) -> int:
    return len(text.split())


def _evaluate_refine(scenario: dict, response_data: dict, elapsed_ms: float) -> dict:
    """Evaluate a /refine response."""
    checks_spec = scenario.get("checks", {})
    must_preserve = scenario.get("must_preserve", [])
    expected_tone = scenario.get("expected_tone", "Neutral")
    refined = response_data.get("refined", "")
    original = scenario["request"]["selection"]

    passed = {}

    # Basic structural checks
    if "has_refined" in checks_spec:
        passed["has_refined"] = bool(refined)
    if "not_empty" in checks_spec:
        passed["not_empty"] = len(refined.strip()) > 0
    if "preserves_meaning" in checks_spec:
        keyword = checks_spec["preserves_meaning"]
        passed["preserves_meaning"] = keyword.lower() in refined.lower()

    # Token preservation
    if "preserves_tokens" in checks_spec:
        tokens = checks_spec["preserves_tokens"]
        for token in tokens:
            passed[f"preserves_token:{token}"] = token in refined

    # Forbid tokens (output must NOT contain — catches hallucinated words)
    if "forbid_tokens" in checks_spec:
        for token in checks_spec["forbid_tokens"]:
            passed[f"forbid_token:{token}"] = token not in refined

    # Hebrew preservation (Hebrew input must yield Hebrew output — no stealth translation)
    if checks_spec.get("must_contain_hebrew"):
        passed["must_contain_hebrew"] = any("֐" <= ch <= "׿" for ch in refined)

    # Minimum output length (catches over-summarization)
    if "min_output_words" in checks_spec:
        passed["min_output_words"] = _word_count(refined) >= checks_spec["min_output_words"]

    correctness = _correctness_score(passed)

    # Quality scoring
    orig_words = _word_count(original)
    refined_words = _word_count(refined)
    length_score = _length_stability_score(orig_words, refined_words)

    if expected_tone == "Casual":
        tone_score = _quality_score_casual(refined)
    elif expected_tone == "Professional":
        tone_score = _quality_score_professional(refined)
    else:
        tone_score = 100.0  # Neutral — no heuristic, trust the model

    quality = (tone_score + length_score) / 2.0

    latency = _latency_score(elapsed_ms)
    composite = _composite(correctness, quality, latency)

    return {
        "correctness": correctness,
        "quality": quality,
        "latency_score": latency,
        "composite": composite,
        "elapsed_ms": elapsed_ms,
        "checks_detail": passed,
        "refined": refined,
    }


def _evaluate_dictionary(scenario: dict, response_data: dict, elapsed_ms: float) -> dict:
    """Evaluate a /dictionary response."""
    checks_spec = scenario.get("checks", {})
    candidates = response_data.get("candidates", [])
    query_language = response_data.get("query_language", "")
    expected_language = scenario.get("expected_language", "english")

    passed = {}

    if "has_candidates" in checks_spec:
        passed["has_candidates"] = len(candidates) > 0
    if "min_candidates" in checks_spec:
        passed["min_candidates"] = len(candidates) >= checks_spec["min_candidates"]
    if "has_confidence_field" in checks_spec:
        passed["has_confidence_field"] = all("confidence" in c for c in candidates) if candidates else False
    if "register_match_formal" in checks_spec:
        passed["register_match_formal"] = any(
            c.get("register", "") in ("formal", "professional") for c in candidates
        ) if candidates else False

    # Language detection correctness
    passed["correct_language"] = query_language == expected_language

    correctness = _correctness_score(passed)

    # Quality: has_confidence_field for Hebrew, register coverage
    quality_checks = []
    if expected_language == "hebrew" and candidates:
        all_have_confidence = all("confidence" in c for c in candidates)
        quality_checks.append(100.0 if all_have_confidence else 50.0)
    if candidates:
        has_register = all("register" in c for c in candidates)
        quality_checks.append(100.0 if has_register else 60.0)
        has_example = all("example" in c for c in candidates)
        quality_checks.append(100.0 if has_example else 60.0)

    quality = sum(quality_checks) / len(quality_checks) if quality_checks else 100.0

    latency = _latency_score(elapsed_ms)
    composite = _composite(correctness, quality, latency)

    return {
        "correctness": correctness,
        "quality": quality,
        "latency_score": latency,
        "composite": composite,
        "elapsed_ms": elapsed_ms,
        "checks_detail": passed,
        "candidates": candidates,
    }


def _evaluate_capture_style(scenario: dict, response_data: dict, elapsed_ms: float) -> dict:
    """Evaluate a /capture_style response."""
    checks_spec = scenario.get("checks", {})
    passed = {}
    if "saved_true" in checks_spec:
        passed["saved_true"] = response_data.get("saved") is True

    correctness = _correctness_score(passed)
    latency = _latency_score(elapsed_ms)
    composite = _composite(correctness, 100.0, latency)

    return {
        "correctness": correctness,
        "quality": 100.0,
        "latency_score": latency,
        "composite": composite,
        "elapsed_ms": elapsed_ms,
        "checks_detail": passed,
    }


def _evaluate_undo(scenario: dict, response_data: dict, elapsed_ms: float) -> dict:
    """Evaluate a /refine/undo response."""
    checks_spec = scenario.get("checks", {})
    original_selection = scenario["setup_refine"]["selection"]
    returned_original = response_data.get("original", "")

    passed = {}
    if "original_exact_match" in checks_spec:
        passed["original_exact_match"] = returned_original == original_selection

    correctness = _correctness_score(passed)
    latency = _latency_score(elapsed_ms)
    composite = _composite(correctness, 100.0, latency)

    return {
        "correctness": correctness,
        "quality": 100.0,
        "latency_score": latency,
        "composite": composite,
        "elapsed_ms": elapsed_ms,
        "checks_detail": passed,
    }


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


def _post(path: str, body: dict, timeout: int = 60) -> tuple[int, dict, float]:
    """POST to daemon. Returns (status_code, response_body, elapsed_ms)."""
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{_BASE_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            elapsed_ms = (time.monotonic() - start) * 1000
            body_out = json.loads(resp.read())
            return resp.status, body_out, elapsed_ms
    except urllib.error.HTTPError as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        return exc.code, json.loads(exc.read()), elapsed_ms


def _get_status() -> dict:
    req = urllib.request.Request(f"{_BASE_URL}/status")
    with urllib.request.urlopen(req, timeout=5) as resp:
        outer = json.loads(resp.read())
        return outer.get("data", outer)


# ---------------------------------------------------------------------------
# Pre-run health check
# ---------------------------------------------------------------------------


def _health_check() -> None:
    """Check daemon is up and model is available. Exits on failure."""
    # 1. Check daemon reachability
    try:
        status = _get_status()
    except Exception as exc:
        print(f"ERROR: Cannot reach daemon at {_BASE_URL}/status — {exc}", file=sys.stderr)
        print("Start the daemon with: python -m lingopulse.daemon", file=sys.stderr)
        sys.exit(1)

    model = status.get("model", "unknown")

    # 2. Check ollama has the model pulled at all
    try:
        result = subprocess.run(
            ["ollama", "list"],
            capture_output=True, text=True, timeout=10
        )
        if model not in result.stdout:
            print(f"ERROR: Model '{model}' not found in `ollama list`.", file=sys.stderr)
            print(f"Run: ollama pull {model}", file=sys.stderr)
            sys.exit(1)
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        print(f"WARNING: Could not verify ollama model list — {exc}", file=sys.stderr)

    # 3. If model not loaded, warm it up
    if not status.get("model_loaded", False):
        print(f"Model '{model}' is not loaded in memory. Running warmup (up to 90s)…")
        try:
            code, body, _ = _post(
                "/refine",
                {"selection": "hello", "app": "Slack"},
                timeout=90,
            )
            if code not in (200, 422):
                print(f"ERROR: Warmup failed — daemon returned HTTP {code}", file=sys.stderr)
                sys.exit(1)
            print("Warmup complete.")
        except Exception as exc:
            print(f"ERROR: Model not loaded and warmup failed — {exc}", file=sys.stderr)
            sys.exit(1)


# ---------------------------------------------------------------------------
# Git SHA
# ---------------------------------------------------------------------------


def _git_sha() -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(_REPO_ROOT), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        sha = result.stdout.strip()
        return sha if sha else "unknown"
    except Exception:
        return "unknown"


# ---------------------------------------------------------------------------
# Run command
# ---------------------------------------------------------------------------


def run(out_dir: str = "benchmarks") -> None:
    _health_check()

    scenarios = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
    out_path = pathlib.Path(out_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    sha = _git_sha()
    timestamp = datetime.now(timezone.utc).astimezone().strftime("%Y%m%dT%H%M%S")
    run_id = f"{timestamp}-{sha}"

    results = []
    totals = {"correctness": 0.0, "quality": 0.0, "latency_score": 0.0, "composite": 0.0}
    count = 0

    print(f"Running {len(scenarios)} scenarios (git {sha})…\n")
    print(f"{'ID':<32} {'Corr':>6} {'Qual':>6} {'Lat':>6} {'Comp':>6} {'ms':>8}")
    print("-" * 70)

    for sc in scenarios:
        sc_id = sc["id"]
        endpoint = sc["endpoint"]

        try:
            if endpoint == "refine":
                code, resp, elapsed_ms = _post("/refine", sc["request"])
                if code != 200:
                    raise RuntimeError(f"HTTP {code}: {resp.get('error', resp)}")
                metrics = _evaluate_refine(sc, resp.get("data", {}), elapsed_ms)

            elif endpoint == "dictionary":
                code, resp, elapsed_ms = _post("/dictionary", sc["request"])
                if code != 200:
                    raise RuntimeError(f"HTTP {code}: {resp.get('error', resp)}")
                metrics = _evaluate_dictionary(sc, resp.get("data", {}), elapsed_ms)

            elif endpoint == "capture_style":
                code, resp, elapsed_ms = _post("/capture_style", sc["request"])
                if code != 200:
                    raise RuntimeError(f"HTTP {code}: {resp.get('error', resp)}")
                metrics = _evaluate_capture_style(sc, resp.get("data", {}), elapsed_ms)

            elif endpoint == "undo":
                # First, run the setup refine
                setup = sc["setup_refine"]
                _post("/refine", setup, timeout=60)
                # Then undo
                code, resp, elapsed_ms = _post("/refine/undo", {})
                if code != 200:
                    raise RuntimeError(f"HTTP {code}: {resp.get('error', resp)}")
                metrics = _evaluate_undo(sc, resp.get("data", {}), elapsed_ms)

            else:
                raise ValueError(f"Unknown endpoint: {endpoint}")

            results.append({
                "id": sc_id,
                "endpoint": endpoint,
                "description": sc.get("description", ""),
                "status": "ok",
                **metrics,
            })

            for key in totals:
                totals[key] += metrics[key]
            count += 1

            print(
                f"{sc_id:<32} "
                f"{metrics['correctness']:>6.1f} "
                f"{metrics['quality']:>6.1f} "
                f"{metrics['latency_score']:>6.1f} "
                f"{metrics['composite']:>6} "
                f"{metrics['elapsed_ms']:>8.0f}"
            )

        except Exception as exc:
            results.append({
                "id": sc_id,
                "endpoint": endpoint,
                "description": sc.get("description", ""),
                "status": "error",
                "error": str(exc),
                "correctness": 0.0,
                "quality": 0.0,
                "latency_score": 0.0,
                "composite": 0,
                "elapsed_ms": 0.0,
            })
            print(f"{sc_id:<32} {'ERR':>6} {'ERR':>6} {'ERR':>6} {'ERR':>6} {'—':>8}  {exc}")

    # Aggregate
    if count:
        avg = {k: v / count for k, v in totals.items()}
    else:
        avg = {k: 0.0 for k in totals}

    print("-" * 70)
    print(
        f"{'AVERAGE':<32} "
        f"{avg['correctness']:>6.1f} "
        f"{avg['quality']:>6.1f} "
        f"{avg['latency_score']:>6.1f} "
        f"{avg['composite']:>6.1f}"
    )
    print()

    latencies = [r["elapsed_ms"] for r in results if r["status"] == "ok"]
    if latencies:
        print(f"Latency  p50={sorted(latencies)[len(latencies)//2]:.0f}ms  "
              f"p95={sorted(latencies)[int(len(latencies)*0.95)]:.0f}ms  "
              f"max={max(latencies):.0f}ms")

    # Save output
    output = {
        "run_id": run_id,
        "git_sha": sha,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "scenario_count": len(scenarios),
        "ok_count": count,
        "averages": avg,
        "latency_p50": sorted(latencies)[len(latencies) // 2] if latencies else None,
        "latency_p95": sorted(latencies)[int(len(latencies) * 0.95)] if latencies else None,
        "latency_max": max(latencies) if latencies else None,
        "results": results,
    }

    out_file = out_path / f"run-{run_id}.json"
    out_file.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nSaved → {out_file}")


# ---------------------------------------------------------------------------
# Compare command
# ---------------------------------------------------------------------------


def _ansi(text: str, code: str, use_color: bool) -> str:
    if not use_color:
        return text
    return f"\033[{code}m{text}\033[0m"


def _delta_str(delta: float, use_color: bool) -> str:
    if delta > 0:
        return _ansi(f"+{delta:.1f}", "32", use_color)
    if delta < 0:
        return _ansi(f"{delta:.1f}", "31", use_color)
    return "0.0"


def compare(file_a: str | None, file_b: str | None) -> None:
    bench_dir = _REPO_ROOT / "benchmarks"
    use_color = sys.stdout.isatty()

    if file_a is None and file_b is None:
        # Find two most recent run files
        run_files = sorted(
            [f for f in bench_dir.glob("run-*.json")],
            key=lambda f: f.stat().st_mtime,
            reverse=True,
        )
        if len(run_files) < 2:
            print("ERROR: Need at least 2 run files in benchmarks/ to compare.", file=sys.stderr)
            sys.exit(1)
        path_b = run_files[0]  # newer
        path_a = run_files[1]  # older
    elif file_a is not None and file_b is not None:
        path_a = pathlib.Path(file_a)
        path_b = pathlib.Path(file_b)
    else:
        print("ERROR: Provide 0 or 2 file paths.", file=sys.stderr)
        sys.exit(1)

    data_a = json.loads(path_a.read_text(encoding="utf-8"))
    data_b = json.loads(path_b.read_text(encoding="utf-8"))

    avg_a = data_a.get("averages", {})
    avg_b = data_b.get("averages", {})

    print(f"\nComparing runs:")
    print(f"  A: {path_a.name}  (git {data_a.get('git_sha', '?')})")
    print(f"  B: {path_b.name}  (git {data_b.get('git_sha', '?')})")
    print()

    header = f"{'Dimension':<22} {'A':>8} {'B':>8} {'Δ':>10}"
    print(header)
    print("-" * len(header))

    dims = [
        ("Correctness", "correctness"),
        ("Quality", "quality"),
        ("Latency Score", "latency_score"),
        ("Composite", "composite"),
    ]
    for label, key in dims:
        va = avg_a.get(key, 0.0)
        vb = avg_b.get(key, 0.0)
        delta = vb - va
        print(f"{label:<22} {va:>8.1f} {vb:>8.1f} {_delta_str(delta, use_color):>10}")

    print()
    # Latency metrics rows
    lat_header = f"{'Latency metric':<22} {'A':>8} {'B':>8} {'Δ':>10}"
    print(lat_header)
    print("-" * len(lat_header))

    def _lat(data: dict, key: str) -> float:
        v = data.get(key)
        return v if v is not None else float("nan")

    lat_rows = [
        ("p50 (ms)", "latency_p50"),
        ("p95 (ms)", "latency_p95"),
        ("max (ms)", "latency_max"),
    ]
    for label, key in lat_rows:
        va = _lat(data_a, key)
        vb = _lat(data_b, key)
        if va != va or vb != vb:  # nan check
            print(f"{label:<22} {'N/A':>8} {'N/A':>8} {'N/A':>10}")
            continue
        delta = vb - va
        # For latency: lower is better, so negate delta sign for color
        if delta < 0:
            dstr = _ansi(f"{delta:.0f}", "32", use_color)   # green = improvement
        elif delta > 0:
            dstr = _ansi(f"+{delta:.0f}", "31", use_color)  # red = regression
        else:
            dstr = "0"
        print(f"{label:<22} {va:>8.0f} {vb:>8.0f} {dstr:>10}")


# ---------------------------------------------------------------------------
# List command
# ---------------------------------------------------------------------------


def list_runs() -> None:
    bench_dir = _REPO_ROOT / "benchmarks"
    run_files = sorted(
        [f for f in bench_dir.glob("run-*.json")],
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )
    if not run_files:
        print("No benchmark runs found in benchmarks/")
        return

    print(f"{'File':<50} {'Timestamp':<25} {'Composite':>10} {'Scenarios':>10}")
    print("-" * 100)
    for f in run_files:
        data = json.loads(f.read_text(encoding="utf-8"))
        avg = data.get("averages", {})
        composite = avg.get("composite", 0.0)
        ts = data.get("timestamp", "unknown")
        n = data.get("scenario_count", "?")
        print(f"{f.name:<50} {ts:<25} {composite:>10.1f} {str(n):>10}")


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def main():
    import argparse
    parser = argparse.ArgumentParser(prog="lingopulse.benchmark")
    sub = parser.add_subparsers(dest="cmd", required=True)
    run_p = sub.add_parser("run")
    run_p.add_argument("--out", default="benchmarks")
    cmp = sub.add_parser("compare")
    cmp.add_argument("file_a", nargs="?")
    cmp.add_argument("file_b", nargs="?")
    sub.add_parser("list")
    args = parser.parse_args()
    if args.cmd == "run":
        run(out_dir=args.out)
    elif args.cmd == "compare":
        compare(args.file_a, args.file_b)
    elif args.cmd == "list":
        list_runs()


if __name__ == "__main__":
    main()
