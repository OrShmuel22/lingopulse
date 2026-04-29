#!/usr/bin/env python3
"""Harder typo battery — words that are NOT in the prompt's few-shot examples.

Verifies the model can generalize beyond the in-prompt examples.

Usage: python3 benchmarks/quality_check_hard.py [model]
"""
from __future__ import annotations

import sys
import importlib.util
from pathlib import Path

# Reuse build_prompt + call_ollama + grade from quality_check.py
spec = importlib.util.spec_from_file_location(
    "qc",
    Path(__file__).parent / "quality_check.py",
)
qc = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(qc)

# 20 typos NOT mentioned anywhere in the prompt or examples.
HARD_CASES = [
    {"id": 1, "desc": "definately → definitely",          "input": "i will definately be there tomorrow",
     "must_contain": ["definitely"], "must_not_contain": ["definately"]},
    {"id": 2, "desc": "occured → occurred",                "input": "the bug occured during the build step",
     "must_contain": ["occurred"], "must_not_contain": ["occured"]},
    {"id": 3, "desc": "accomodate → accommodate",          "input": "the room can accomodate ten people",
     "must_contain": ["accommodate"], "must_not_contain": ["accomodate"]},
    {"id": 4, "desc": "tommorow → tomorrow",               "input": "see you tommorow at the standup",
     "must_contain": ["tomorrow"], "must_not_contain": ["tommorow"]},
    {"id": 5, "desc": "wierd → weird",                     "input": "this is a wierd error message",
     "must_contain": ["weird"], "must_not_contain": ["wierd"]},
    {"id": 6, "desc": "untill → until",                    "input": "lets wait untill the CI finishes",
     "must_contain": ["until"], "must_not_contain": ["untill"]},
    {"id": 7, "desc": "suprise → surprise",                "input": "the rollout was a suprise to everyone",
     "must_contain": ["surprise"], "must_not_contain": ["suprise"]},
    {"id": 8, "desc": "enviroment → environment",          "input": "deploy to staging enviroment first",
     "must_contain": ["environment"], "must_not_contain": ["enviroment"]},
    {"id": 9, "desc": "compatable → compatible",           "input": "is the new SDK compatable with our setup",
     "must_contain": ["compatible"], "must_not_contain": ["compatable"]},
    {"id": 10, "desc": "priviledge → privilege",           "input": "i need root priviledge for this",
     "must_contain": ["privilege"], "must_not_contain": ["priviledge"]},
    {"id": 11, "desc": "embarass → embarrass",             "input": "dont embarass yourself in the meeting",
     "must_contain": ["embarrass"], "must_not_contain": ["embarass"]},
    {"id": 12, "desc": "concious → conscious",             "input": "be more concious of the deadlines",
     "must_contain": ["conscious"], "must_not_contain": ["concious"]},
    {"id": 13, "desc": "arguement → argument",             "input": "his arguement makes no sense",
     "must_contain": ["argument"], "must_not_contain": ["arguement"]},
    {"id": 14, "desc": "relevent → relevant",              "input": "this is not relevent to the bug",
     "must_contain": ["relevant"], "must_not_contain": ["relevent"]},
    {"id": 15, "desc": "paralel → parallel",               "input": "we can run those tests in paralel",
     "must_contain": ["parallel"], "must_not_contain": ["paralel"]},
    {"id": 16, "desc": "truely → truly",                   "input": "i am truely sorry for the delay",
     "must_contain": ["truly"], "must_not_contain": ["truely"]},
    {"id": 17, "desc": "sieze → seize",                    "input": "we should sieze the opportunity",
     "must_contain": ["seize"], "must_not_contain": ["sieze"]},
    {"id": 18, "desc": "mispell → misspell",               "input": "i always mispell that word",
     "must_contain": ["misspell"], "must_not_contain": ["mispell"]},
    {"id": 19, "desc": "liason → liaison",                 "input": "shes our liason with the vendor",
     "must_contain": ["liaison"], "must_not_contain": ["liason"]},
    {"id": 20, "desc": "noticable → noticeable",           "input": "the regression is noticable in prod",
     "must_contain": ["noticeable"], "must_not_contain": ["noticable"]},
]

# Bonus: rerun the in-prompt typo `spreate` 5 times to test determinism.
SPREATE_RUNS = 5


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else qc.DEFAULT_MODEL
    print(f"Hard typo battery against {model} — {len(HARD_CASES)} cases\n")

    passed = 0
    total_time = 0.0

    for case in HARD_CASES:
        prompt = qc.build_prompt(case["input"])
        try:
            output, dt = qc.call_ollama(model, prompt)
        except Exception as e:
            print(f"[{case['id']:2}] ERROR  {case['desc']}  ->  {e}")
            continue
        total_time += dt
        fails = qc.grade(case, output)
        verdict = "PASS" if not fails else "FAIL"
        print(f"[{case['id']:2}] {verdict}  ({dt:5.2f}s)  {case['desc']}")
        print(f"     in : {case['input']}")
        print(f"     out: {output}")
        if fails:
            print(f"     >>>: {'; '.join(fails)}")
        else:
            passed += 1
        print()

    print("=" * 70)
    print(f"Hard battery: {passed}/{len(HARD_CASES)} passed   total {total_time:.1f}s   avg {total_time/len(HARD_CASES):.2f}s/case\n")

    # `spreate` repeatability — was it real understanding or just one lucky pattern-match?
    print(f"Determinism check — running 'I spreate the PR for clarity' x{SPREATE_RUNS}:\n")
    fixes = 0
    for i in range(SPREATE_RUNS):
        prompt = qc.build_prompt("I spreate the PR for clarity")
        out, dt = qc.call_ollama(model, prompt)
        fixed = "spreate" not in out and "separate" in out
        if fixed:
            fixes += 1
        print(f"  run {i+1}: ({dt:4.2f}s) {'PASS' if fixed else 'FAIL'} -> {out}")
    print(f"\n  -> {fixes}/{SPREATE_RUNS} runs fixed `spreate`")


if __name__ == "__main__":
    main()
