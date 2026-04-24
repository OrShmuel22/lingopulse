import json
import re

DICTIONARY_EN_PROMPT = """You help a user find precise English words from a description.
Return exactly 3 word candidates as a JSON array. For each candidate:
  "word": the English word or short phrase
  "example": one brief sentence showing the word in use
  "register": one of "casual", "neutral", "formal", "technical"
Prefer words the user is likely looking for over archaic or obscure options.
Preserve existing English words from the query if they're already correct.

Query: {query}

Return only the JSON array. No preamble."""

DICTIONARY_HE_PROMPT = """You help a native Hebrew speaker find precise English words.
The user has typed a description that may include Hebrew, English, or both.
Return up to 3 word candidates as a JSON array. For each:
  "word": the English word or short phrase
  "example": one brief sentence showing the word in use
  "register": one of "casual", "neutral", "formal", "technical"
  "confidence": one of "high", "low"

Rules:
- If you are uncertain about a translation, set confidence="low" and still include it.
- If you would be guessing, return fewer than 3 candidates rather than padding with uncertain options.
- Be conservative: prefer common, current words over archaic or rare ones.

Query: {query}

Return only the JSON array. No preamble."""


def detect_hebrew(text: str) -> bool:
    return bool(re.search(r"[֐-׿]", text))


def build_prompt(query: str) -> str:
    if detect_hebrew(query):
        return DICTIONARY_HE_PROMPT.format(query=query)
    return DICTIONARY_EN_PROMPT.format(query=query)


def parse_response(raw: str) -> list[dict]:
    text = raw.strip()

    # Strip markdown fences
    text = re.sub(r"^```[a-zA-Z]*\n?", "", text)
    text = re.sub(r"\n?```$", "", text)
    text = text.strip()

    # Find first [ and last ]
    start = text.find("[")
    end = text.rfind("]")
    if start != -1 and end != -1 and end > start:
        array_str = text[start : end + 1]
        try:
            result = json.loads(array_str)
            if isinstance(result, list):
                return result
        except json.JSONDecodeError:
            pass

    # Regex fallback: extract individual JSON objects
    candidates = []
    for m in re.finditer(r"\{[^{}]+\}", text, re.DOTALL):
        try:
            obj = json.loads(m.group(0))
            if "word" in obj:
                candidates.append(obj)
        except json.JSONDecodeError:
            continue

    return candidates


def render_candidates(candidates: list[dict]) -> str:
    lines = []
    for i, c in enumerate(candidates, 1):
        word = c.get("word", "")
        register = c.get("register", "")
        example = c.get("example", "")
        confidence = c.get("confidence", "high")
        conf_flag = " ⚠️ low confidence" if confidence == "low" else ""
        lines.append(f"{i}. {word} [{register}]{conf_flag}")
        if example:
            lines.append(f'   "{example}"')
        lines.append("")
    return "\n".join(lines).rstrip()
