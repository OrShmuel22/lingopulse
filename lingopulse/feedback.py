import json
from datetime import datetime, timezone
from typing import Iterator

from . import config


VALID_REASONS = {
    "wrong_meaning",
    "too_formal",
    "too_casual",
    "lost_voice",
    "tech_term_changed",
    "tone_mismatch",
    "over_summarized",
    "added_content",
    "other",
}


def _path():
    return config.path_for("feedback.path")


def append(
    input_text: str,
    rejected_output: str,
    reason: str,
    app: str = "",
    tone: str = "",
    note: str = "",
) -> dict:
    if not input_text:
        raise ValueError("input_text must be non-empty")
    if not rejected_output:
        raise ValueError("rejected_output must be non-empty")
    if reason not in VALID_REASONS:
        raise ValueError(f"reason must be one of {sorted(VALID_REASONS)}, got {reason!r}")

    entry = {
        "timestamp": datetime.now(timezone.utc).astimezone().isoformat(),
        "input": input_text,
        "rejected_output": rejected_output,
        "reason": reason,
        "app": app,
        "tone": tone,
        "note": note,
    }

    path = _path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        f.flush()
    return entry


def iter_entries() -> Iterator[dict]:
    path = _path()
    if not path.exists():
        return
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def read_all() -> list[dict]:
    return list(iter_entries())
