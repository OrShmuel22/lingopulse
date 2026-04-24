import json
import pathlib
from datetime import datetime, timezone
from typing import Iterator

from . import config


def _history_path() -> pathlib.Path:
    return config.path_for("history.path")


def append(entry: dict) -> None:
    if "timestamp" not in entry:
        entry = dict(entry)
        entry["timestamp"] = datetime.now(timezone.utc).astimezone().isoformat()

    path = _history_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        f.flush()


def read_all() -> list[dict]:
    return list(iter_entries())


def iter_entries() -> Iterator[dict]:
    path = _history_path()
    if not path.exists():
        return

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)
