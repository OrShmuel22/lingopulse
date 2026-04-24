import re
import secrets
from dataclasses import dataclass, field


@dataclass
class ProtectedText:
    redacted: str
    tokens: dict[str, str]


class ProtectionError(Exception):
    pass


_PATTERNS = [
    re.compile(r"```[\s\S]*?```"),
    re.compile(r"https?://\S+"),
    re.compile(r"`[^`\n]+`"),
]


def protect(text: str) -> ProtectedText:
    tokens: dict[str, str] = {}
    result = text
    for pattern in _PATTERNS:
        def _replace(m: re.Match) -> str:
            placeholder = f"⟨⟨LP:{secrets.token_hex(3)}⟩⟩"
            tokens[placeholder] = m.group(0)
            return placeholder
        result = pattern.sub(_replace, result)
    return ProtectedText(redacted=result, tokens=tokens)


def restore(text: str, tokens: dict[str, str]) -> str:
    for placeholder, original in tokens.items():
        if placeholder not in text:
            raise ProtectionError(f"Placeholder {placeholder!r} missing from text")
        text = text.replace(placeholder, original)
    return text
