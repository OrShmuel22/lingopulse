import difflib
import re


_CALQUE_PATTERNS = {
    ("responsible", "on"): ("responsible", "for", "preposition", "Hebrew calque: 'responsible on' → 'responsible for'"),
    ("depend", "on"): None,
    ("interested", "to"): ("interested", "in", "preposition", "Hebrew calque: 'interested to' → 'interested in'"),
    ("until", None): ("by", None, "preposition", "Hebrew calque: 'until X' often should be 'by X'"),
    ("informations",): ("information", None, "plural", "'information' is uncountable"),
    ("feedbacks",): ("feedback", None, "plural", "'feedback' is uncountable"),
    ("advices",): ("advice", None, "plural", "'advice' is uncountable"),
    ("softwares",): ("software", None, "plural", "'software' is uncountable"),
    ("equipments",): ("equipment", None, "plural", "'equipment' is uncountable"),
    ("more", "bigger"): ("bigger", None, "comparative", "Double comparative"),
    ("more", "better"): ("better", None, "comparative", "Double comparative"),
}

_PLURAL_UNCOUNTABLES = {"informations", "feedbacks", "advices", "softwares", "equipments", "researches", "progresses"}

_PREPOSITION_HINTS = {"on", "in", "at", "to", "from", "for", "with", "of", "about"}


def _classify(from_text: str, to_text: str) -> tuple[str, str]:
    """Return (category, reason) for an edit."""
    from_low = from_text.lower().strip()
    to_low = to_text.lower().strip()

    if from_low in _PLURAL_UNCOUNTABLES and to_low == from_low.rstrip("s"):
        return ("plural", f"'{from_text}' is uncountable in English")

    if from_low in _PREPOSITION_HINTS and to_low in _PREPOSITION_HINTS:
        return ("preposition", f"Wrong preposition: '{from_text}' → '{to_text}'")

    from_words = from_low.split()
    to_words = to_low.split()
    if len(from_words) >= 2 and len(to_words) >= 2:
        if from_words[0] == to_words[0] and from_words[-1] != to_words[-1] and from_words[-1] in _PREPOSITION_HINTS:
            return ("preposition", f"Wrong preposition: '{from_words[-1]}' → '{to_words[-1]}'")

    if from_low.startswith("until ") and to_low.startswith("by "):
        return ("calque", "Hebrew calque: 'until X' → 'by X'")

    if from_low in {"i want that you will", "i want that you"}:
        return ("structure", "Hebrew sentence structure: use 'please X' or 'could you X'")

    if "'" in to_text and from_low == to_low.replace("'", ""):
        return ("apostrophe", "Missing apostrophe in contraction")

    if from_text != to_text and from_text.lower() == to_text.lower():
        return ("capitalization", f"Capitalization: '{from_text}' → '{to_text}'")

    if to_low == from_low + "s" or to_low + "s" == from_low:
        return ("plural", "Plural agreement")

    if abs(len(from_text) - len(to_text)) <= 3 and _similar(from_low, to_low) > 0.7:
        return ("typo", f"Likely typo: '{from_text}' → '{to_text}'")

    return ("grammar", f"'{from_text}' → '{to_text}'")


def _similar(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a, b).ratio()


def _tokenize(text: str) -> list[str]:
    return text.split()


def compute_edits(original: str, refined: str) -> list[dict]:
    """Diff two strings at word level. Return list of structured edits."""
    if original == refined:
        return []

    orig_words = _tokenize(original)
    ref_words = _tokenize(refined)

    matcher = difflib.SequenceMatcher(a=orig_words, b=ref_words, autojunk=False)
    edits: list[dict] = []

    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            continue

        from_words = orig_words[i1:i2]
        to_words = ref_words[j1:j2]
        from_text = " ".join(from_words)
        to_text = " ".join(to_words)

        if op == "replace":
            edit_type = "replace"
        elif op == "delete":
            edit_type = "delete"
        elif op == "insert":
            edit_type = "insert"
        else:
            continue

        category, reason = _classify(from_text, to_text)

        edits.append({
            "type": edit_type,
            "from_text": from_text,
            "to_text": to_text,
            "from_span": [i1, i2],
            "to_span": [j1, j2],
            "category": category,
            "reason": reason,
        })

    return edits


def apply_edits(original: str, refined: str, accepted_indices: list[int]) -> str:
    """Apply a subset of edits by index. Edits not in accepted_indices are reverted to original."""
    if not accepted_indices:
        return original

    all_edits = compute_edits(original, refined)
    if not all_edits:
        return refined

    accepted_set = set(accepted_indices)
    if accepted_set == set(range(len(all_edits))):
        return refined

    orig_words = _tokenize(original)
    ref_words = _tokenize(refined)
    matcher = difflib.SequenceMatcher(a=orig_words, b=ref_words, autojunk=False)

    result_words: list[str] = []
    edit_idx = 0
    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            result_words.extend(orig_words[i1:i2])
        else:
            if edit_idx in accepted_set:
                result_words.extend(ref_words[j1:j2])
            else:
                result_words.extend(orig_words[i1:i2])
            edit_idx += 1

    return " ".join(result_words)
