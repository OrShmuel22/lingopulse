#!/usr/bin/env python3
"""LingoPulse refine-quality smoke test.

Hits Ollama with the same prompt + sampling LingoPulse uses for the Casual
tone, runs 20 graded cases (varying typo / grammar / capitalization /
preservation difficulty), and prints pass/fail per case plus a summary.

The fixer templates here are inlined copies of Prompts.swift —
keep in sync if you change the Swift side.

Usage:  python3 benchmarks/quality_check.py [model]
        # default model is gemma4:e4b
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.request

OLLAMA_HOST = "http://127.0.0.1:11434"
DEFAULT_MODEL = "gemma4:e4b"

# Mirrors the rewrite template in Prompts.swift (used for non-Grammar-only tones).
REWRITE_TEMPLATE = """You fix English errors and adjust the text to match the requested tone.
You preserve everything else.

Rules:
1. Fix all unambiguous errors:
   - Spelling typos (spreate → separate, recieve → receive, freind → friend).
   - Grammar (subject-verb agreement, tense, articles, plurals, pronoun
     case, fragments, run-ons).
   - Punctuation (missing commas, periods, apostrophes).
   - Wrong-word errors (your/you're, its/it's, depend of → depend on).
   - Awkward phrasing that has no grammatical reading (e.g. "I spreate
     PR" → "I made a separate PR").
2. Same number of sentences in output as input.
3. If input is fully correct AND already matches the tone, output = input.
   Otherwise, fix everything you are confident about.
4. Keep code, URLs, file paths, emails, names, technical terms, and
   non-English text (including Hebrew) byte-for-byte verbatim.
5. Preserve regional spelling (UK vs US) — keep what the author used.
6. Capitalization is correctness, not a tone choice.
   - ADD missing capitals: lowercase pronoun "i" → "I"; lowercase
     sentence-initial → uppercase; lowercase proper nouns / brand names
     that should be capitalized.
   - PRESERVE author-written capitals: acronyms and initialisms (PR,
     API, URL, AWS, MR, CI), product names with intentional casing
     (cycode-common, iPhone, npm), and any uppercase the author used.
   - Never lowercase something the author wrote uppercase.
7. Match the requested tone described in the context block below, but
   only adjust phrasing — never strip capitalization or punctuation that
   was already correct, and never invent informality by removing capitals.
8. Output the result only. No preamble, no commentary, no markdown unless
   it was in the input.

Examples:

Input:  who is responsible on staging?
Output: who is responsible for staging?

Input:  i have informations and feedbacks
Output: I have information and feedback.

Input:  Visit https://example.com for the docs.
Output: Visit https://example.com for the docs.

Input:  ok so the PR is ready for review and i updated the cycode-common i spreate PR because i want it to be more clean
Output: OK, so the PR is ready for review and I updated cycode-common. I made a separate PR because I want it to be cleaner.

Input:  i recieve the email yesterday and forgot to reply
Output: I received the email yesterday and forgot to reply.

---
App: {app}
Tone: {tone_name} — {tone_description}

Input:  {message}
Output:
"""

CASUAL_DESCRIPTION = (
    'concise, friendly, conversational — keep informal phrasing the author '
    'already used; capitalize the pronoun "I", proper nouns, and acronyms '
    'when missing, but never strip capitals the author already wrote'
)

THOUGHT_RE = re.compile(r"<\|channel>.*?<channel\|>|<\|think\|>", flags=re.DOTALL)


def build_prompt(message: str, app: str = "Slack", tone: str = "Casual") -> str:
    return (
        REWRITE_TEMPLATE
        .replace("{app}", app)
        .replace("{tone_name}", tone)
        .replace("{tone_description}", CASUAL_DESCRIPTION)
        .replace("{message}", message)
    )


def call_ollama(model: str, prompt: str, timeout: float = 120.0) -> tuple[str, float]:
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "keep_alive": "10m",
        "think": False,
        "options": {
            "temperature": 0.1,
            "top_p": 0.9,
            "top_k": 40,
            "repeat_penalty": 1.0,
            "num_predict": 512,
            "stop": ["\nInput:", "\n\n", "\nOutput:"],
        },
    }
    req = urllib.request.Request(
        f"{OLLAMA_HOST}/api/generate",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.load(resp)
    dt = time.time() - t0
    raw = data.get("response", "")
    cleaned = THOUGHT_RE.sub("", raw).strip()
    # Some models echo the "Output:" framing; strip stray leading tag.
    cleaned = re.sub(r"^Output:\s*", "", cleaned)
    return cleaned, dt


# Each case is graded against criteria that approximate "what a human reviewer
# would check". must_contain / must_not_contain are case-sensitive substrings.
# must_match / must_not_match are full-string regex (re.search).
CASES = [
    # 1. Pronoun i → I (capitalize) + missing article
    {
        "id": 1,
        "desc": "Pronoun 'i' → 'I' + missing article",
        "input": "i went to store",
        "must_match": [r"\bI\b", r"\bwent\b"],
        "must_not_match": [r"\bi\b"],
    },
    # 2. Subject-verb agreement: was/were + their/they're
    {
        "id": 2,
        "desc": "Subject-verb + their/they're",
        "input": "We was happy with the results, but their not final yet.",
        "must_contain": ["were"],
        "must_match": [r"\bthey'?re\b"],
        "must_not_contain": ["was happy"],
    },
    # 3. Spelling typo dist=2 (recieve)
    {
        "id": 3,
        "desc": "Common typo: recieve → received",
        "input": "i recieve the email yesterday",
        "must_contain": ["received"],
        "must_not_contain": ["recieve"],
    },
    # 4. Spelling typo dist=3 (spreate) — the test that prompted this work
    {
        "id": 4,
        "desc": "Hard typo: spreate → separate",
        "input": "I spreate the PR for clarity",
        "must_contain": ["separate"],
        "must_not_contain": ["spreate"],
    },
    # 5. Acronym preservation under Casual
    {
        "id": 5,
        "desc": "Preserve acronym PR (no lowercasing)",
        "input": "ok so the PR is ready for review",
        "must_contain": ["PR"],
        "must_not_contain": [" pr "],
    },
    # 6. Mixed-case product name preservation
    {
        "id": 6,
        "desc": "Preserve product name 'cycode-common'",
        "input": "i updated cycode-common today",
        "must_contain": ["cycode-common"],
        "must_match": [r"\bI\b"],
    },
    # 7. URL preservation
    {
        "id": 7,
        "desc": "URL preserved verbatim",
        "input": "visit https://example.com/path?q=1 for the docs",
        "must_contain": ["https://example.com/path?q=1"],
    },
    # 8. Code in backticks preservation
    {
        "id": 8,
        "desc": "Backticked code preserved verbatim",
        "input": "Run `git push --force-with-lease` and check.",
        "must_contain": ["`git push --force-with-lease`"],
    },
    # 9. Tense fix
    {
        "id": 9,
        "desc": "Wrong past participle: have went → have gone",
        "input": "I have went there twice already",
        "must_contain": ["have gone"],
        "must_not_contain": ["have went"],
    },
    # 10. Wrong preposition
    {
        "id": 10,
        "desc": "Wrong preposition: depend of → depend on",
        "input": "the result depend of the input",
        "must_contain": ["depend on"],
        "must_not_contain": ["depend of"],
    },
    # 11. Plurals on uncountable nouns
    {
        "id": 11,
        "desc": "Uncountable plurals: informations/feedbacks",
        "input": "i have informations and feedbacks for you",
        "must_contain": ["information", "feedback"],
        "must_not_contain": ["informations", "feedbacks"],
    },
    # 12. Casual slang preserved (no formalizing)
    {
        "id": 12,
        "desc": "Casual slang preserved",
        "input": "lol this thing is sick",
        "must_match": [r"\blol\b"],
        # Should not formalize "sick" to "great/excellent"
        "must_contain": ["sick"],
    },
    # 13. Don't lowercase author's intentional uppercase
    {
        "id": 13,
        "desc": "Preserve author-uppercase 'OK'",
        "input": "OK so the PR is ready",
        "must_contain": ["OK", "PR"],
        "must_not_contain": [" ok ", " pr "],
    },
    # 14. Hebrew passthrough
    {
        "id": 14,
        "desc": "Hebrew preserved verbatim",
        "input": "שלום, can you review this when you has time?",
        "must_contain": ["שלום"],
        "must_match": [r"\bhave\b"],  # should fix "has" → "have"
    },
    # 15. Contraction + spelling typo (Im exited)
    {
        "id": 15,
        "desc": "Contraction + spelling: Im exited → I'm excited",
        "input": "Im exited about the launch!",
        "must_match": [r"I'?m"],
        "must_contain": ["excited"],
        "must_not_contain": ["exited"],
    },
    # 16. Email address preservation
    {
        "id": 16,
        "desc": "Email preserved verbatim",
        "input": "ping me at or.shmuel@cycode.com when ready",
        "must_contain": ["or.shmuel@cycode.com"],
    },
    # 17. Multi-error sentence (the user's original)
    {
        "id": 17,
        "desc": "Multi-error: capitals, typo, grammar, comma",
        "input": "ok so the PR is ready for review and i updated the cycode-common i spreate pr because i want it to be more clean",
        "must_contain": ["PR", "cycode-common", "separate", "cleaner"],
        "must_match": [r"\bI\b"],
        "must_not_contain": ["spreate"],
    },
    # 18. Already-correct text → unchanged or near-identical
    {
        "id": 18,
        "desc": "Already-correct text: minimal change",
        "input": "I'll review the PR tomorrow morning.",
        "must_contain": ["I'll", "PR", "tomorrow morning"],
    },
    # 19. Doesn't / dont
    {
        "id": 19,
        "desc": "Contraction agreement: dont → doesn't",
        "input": "she dont like the new design at all",
        "must_match": [r"doesn'?t"],
        "must_not_contain": ["dont"],
    },
    # 20. Their/there
    {
        "id": 20,
        "desc": "Wrong word: their/there",
        "input": "their are too many bugs in the build",
        "must_match": [r"\bThere\b|\bthere\b"],
        "must_not_match": [r"^their\b", r"\btheir are\b"],
    },
]


def grade(case: dict, output: str) -> list[str]:
    """Return list of failure reasons (empty list = pass)."""
    fails = []
    for sub in case.get("must_contain", []):
        if sub not in output:
            fails.append(f"missing '{sub}'")
    for sub in case.get("must_not_contain", []):
        if sub in output:
            fails.append(f"unwanted '{sub}'")
    for pat in case.get("must_match", []):
        if not re.search(pat, output):
            fails.append(f"no match /{pat}/")
    for pat in case.get("must_not_match", []):
        if re.search(pat, output):
            fails.append(f"unwanted match /{pat}/")
    return fails


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MODEL
    print(f"Quality check against {model} — {len(CASES)} cases\n")

    passed = 0
    total_time = 0.0

    for case in CASES:
        prompt = build_prompt(case["input"])
        try:
            output, dt = call_ollama(model, prompt)
        except Exception as e:
            print(f"[{case['id']:2}] ERROR  {case['desc']!r}  ->  {e}")
            continue
        total_time += dt
        fails = grade(case, output)

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
    print(f"Result: {passed}/{len(CASES)} passed   total {total_time:.1f}s   avg {total_time/len(CASES):.2f}s/case")


if __name__ == "__main__":
    main()
