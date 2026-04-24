import re

TONE_DESCRIPTIONS = {
    "Casual": "concise, friendly, lowercase allowed, minimal punctuation",
    "Neutral": "balanced clarity and grammar",
    "Technical": "precise, imperative, documentation-style, clear logic; preserve code identifiers and technical terms",
    "Professional": "polite, structured, standard business English",
    "Grammar-only": "fix grammar and spelling only; do not change tone or wording unless grammatically required",
}

FIXER_PROMPT_TEMPLATE = """You are a careful English editor. The user typed this message in {app}.
Typical register for this app is: {tone_name} — {tone_description}.

BUT: if the original message shows clear signals of a different register — full sentences and formal address (→ preserve formal), legal/compliance language (→ preserve serious), technical acronyms or code identifiers (→ preserve technical) — adjust to match the user's intent rather than the app default.

Do not change the meaning. Do not add, remove, or rephrase content beyond what's needed for clarity and correctness. Preserve all technical terms, code identifiers, URLs, and proper nouns verbatim.

Message:
---
{message}
---

Return only the refined message. No preamble, no explanation."""

_CODE_KEYWORDS = re.compile(
    r"\b(function|const|let|var|class|import|def|return|if|else|for|while|async|await|public|private|null|None|true|false)\b"
)
_CODE_CHARS = re.compile(r"[{}()\[\];=<>/|]")
_COMMENT_MARKERS = re.compile(r"^(//|#|/\*|--)", re.MULTILINE)


def classify_selection(text: str) -> str:
    if "```" in text:
        return "code"

    non_ws = re.sub(r"\s", "", text)
    if non_ws and len(_CODE_CHARS.findall(text)) / len(non_ws) > 0.15:
        return "code"

    first_line = text.lstrip()
    if _COMMENT_MARKERS.match(first_line):
        return "code"

    lines_with_keywords: set[int] = set()
    for m in _CODE_KEYWORDS.finditer(text):
        line_num = text[: m.start()].count("\n")
        lines_with_keywords.add(line_num)
    if len(lines_with_keywords) >= 2:
        return "code"

    return "prose"


def tone_for_app(app: str, selection: str, config: dict) -> str:
    app_map: dict = config.get("tone", {}).get("app_map", {})
    default_tone: str = config.get("tone", {}).get("default_tone", "Neutral")

    tone = app_map.get(app, default_tone)

    if tone == "auto":
        kind = classify_selection(selection)
        return "Technical" if kind == "code" else "Casual"

    return tone


def build_fixer_prompt(app: str, tone: str, message: str) -> str:
    return FIXER_PROMPT_TEMPLATE.format(
        app=app,
        tone_name=tone,
        tone_description=TONE_DESCRIPTIONS.get(tone, "balanced clarity and grammar"),
        message=message,
    )
