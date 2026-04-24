import fcntl
import json
import pathlib
from typing import Callable


class RingBuffer:
    def __init__(self, path: pathlib.Path, size: int = 5):
        self._path = path
        self._size = size

    def _read(self, f) -> list[dict]:
        f.seek(0)
        raw = f.read()
        if not raw:
            return []
        return json.loads(raw).get("entries", [])

    def _write(self, f, entries: list[dict]) -> None:
        f.seek(0)
        f.truncate()
        f.write(json.dumps({"entries": entries}, ensure_ascii=False))
        f.flush()

    def append(self, entry: dict) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._path.open("a+", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            entries = self._read(f)
            entries.append(entry)
            if len(entries) > self._size:
                entries = entries[-self._size:]
            self._write(f, entries)

    def pop_latest(self) -> dict | None:
        if not self._path.exists():
            return None
        with self._path.open("r+", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            entries = self._read(f)
            if not entries:
                return None
            entry = entries.pop()
            self._write(f, entries)
            return entry

    def list_all(self) -> list[dict]:
        if not self._path.exists():
            return []
        with self._path.open("r", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            entries = self._read(f)
        return list(reversed(entries))

    def find_matching(self, predicate: Callable[[dict], bool]) -> dict | None:
        for entry in self.list_all():
            if predicate(entry):
                return entry
        return None
