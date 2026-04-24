import re

_HEBREW_RE = re.compile(r"[֐-׿]")
_CONTRACTION_RE = re.compile(r"\b(i'm|don't|can't|won't|it's|i've|i'll|isn't|aren't|wasn't|weren't|haven't|hadn't|couldn't|wouldn't|shouldn't|didn't|doesn't|i'd)\b", re.IGNORECASE)
_SENTENCE_END_RE = re.compile(r"[.!?]")


def _split_sentences(text: str) -> list[str]:
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p for p in parts if p]


def detect_register(text: str) -> str:
    if _HEBREW_RE.search(text):
        return "hebrew"

    sentences = _split_sentences(text)
    if not sentences:
        return "neutral"

    lowercase_starts = sum(1 for s in sentences if s and s[0].islower())
    lowercase_ratio = lowercase_starts / len(sentences)

    has_contractions = bool(_CONTRACTION_RE.search(text))
    word_counts = [len(s.split()) for s in sentences]
    mean_words = sum(word_counts) / len(word_counts) if word_counts else 0
    short_sentences = mean_words <= 10

    if lowercase_ratio > 0.5:
        return "casual"

    all_end_with_punct = all(_SENTENCE_END_RE.search(s) for s in sentences)
    if all_end_with_punct and mean_words > 15:
        return "formal"

    if has_contractions and short_sentences:
        return "casual"

    return "neutral"


def needs_shift(
    text: str,
    app: str,
    tone_override: str | None = None,
) -> tuple[bool, str]:
    current = detect_register(text)

    if current == "hebrew":
        return (False, "hebrew")

    if tone_override is not None:
        target = tone_override
        if _registers_match(current, target):
            return (False, target)
        return (True, target)

    from . import config as _config
    cfg = _config.get()
    app_map: dict = cfg.get("tone", {}).get("app_map", {})
    default_tone: str = cfg.get("tone", {}).get("default_tone", "Neutral")
    target = app_map.get(app, default_tone)

    if target == "auto":
        from .prompts import classify_selection
        kind = classify_selection(text)
        target = "Technical" if kind == "code" else "Casual"

    if _registers_match(current, target):
        return (False, target)
    return (True, target)


def _registers_match(detected: str, target: str) -> bool:
    target_lower = target.lower()
    if target_lower in ("casual", "neutral"):
        return detected in ("casual", "neutral")
    if target_lower == "formal" or target_lower == "professional":
        return detected == "formal"
    return detected == target_lower
