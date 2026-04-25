import re

TONE_DESCRIPTIONS = {
    "Casual": "concise, friendly, lowercase allowed, minimal punctuation",
    "Neutral": "balanced clarity and grammar",
    "Technical": "precise, imperative, documentation-style, clear logic; preserve code identifiers and technical terms",
    "Professional": "polite, structured, standard business English",
    "Grammar-only": "fix grammar and spelling only; do not change tone or wording unless grammatically required",
}

FIXER_PROMPT_TEMPLATE = """You fix English errors. You preserve everything else.

Rules:
1. Same number of sentences in output as input.
2. If input is correct, output = input. Do not rephrase clean text.
3. Keep code, URLs, names, technical terms, and Hebrew text verbatim.
4. Match the original tone — {tone_description}.

App: {app}
Tone: {tone_name}

Examples:

Input:  who is responsible on staging?
Output: who is responsible for staging?

Input:  i have informations and feedbacks
Output: i have information and feedback

Input:  Ok, I've tested the app; there are small fixes.
Output: Ok, I've tested the app; there are small fixes.

Input:  {message}
Output:"""

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
