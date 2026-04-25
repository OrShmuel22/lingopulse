import json
from datetime import datetime, timezone

from . import config


def _path():
    return config.path_for("personal_dict.path")


def _load_raw() -> list[dict]:
    path = _path()
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("tokens", [])


def _save_raw(tokens: list[dict]) -> None:
    path = _path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"tokens": tokens}, ensure_ascii=False, indent=2), encoding="utf-8")


def list_all() -> list[dict]:
    return _load_raw()


def add(token: str, scope: str = "*") -> dict:
    if not token:
        raise ValueError("token must be non-empty")
    tokens = _load_raw()
    for entry in tokens:
        if entry["token"] == token and entry["scope"] == scope:
            return entry
    entry = {
        "token": token,
        "scope": scope,
        "added_at": datetime.now(timezone.utc).astimezone().isoformat(),
    }
    tokens.append(entry)
    _save_raw(tokens)
    return entry


def remove(token: str, scope: str | None = None) -> int:
    tokens = _load_raw()
    if scope is None:
        kept = [t for t in tokens if t["token"] != token]
    else:
        kept = [t for t in tokens if not (t["token"] == token and t["scope"] == scope)]
    removed_count = len(tokens) - len(kept)
    if removed_count > 0:
        _save_raw(kept)
    return removed_count


def tokens_for_app(app: str) -> list[str]:
    out = []
    for entry in _load_raw():
        scope = entry["scope"]
        if scope == "*" or scope == app:
            out.append(entry["token"])
    return out
