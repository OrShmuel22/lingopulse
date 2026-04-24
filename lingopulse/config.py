import json
import pathlib

DEFAULTS = {
    "fixer": {
        "model": "gemma3:4b-it-qat",
        "timeout_seconds": 15
    },
    "dictionary": {
        "model": "gemma3:4b-it-qat",
        "timeout_seconds": 15
    },
    "keepalive": {
        "enabled": True,
        "ollama_keep_alive": "30m",
        "ping_interval_minutes": 25,
        "active_hours_start": "08:00",
        "active_hours_end": "22:00",
        "login_warmup": True
    },
    "feedback": {
        "hud_show_after_ms": 100,
        "hud_cold_start_notice_after_ms": 2000,
        "hud_error_after_ms": 15000,
        "toast_duration_seconds": 5
    },
    "tone": {
        "default_tone": "Neutral",
        "app_map": {
            "Slack": "Casual",
            "Discord": "Casual",
            "Mail": "Professional",
            "Outlook": "Professional",
            "Cursor": "auto",
            "Code": "auto",
            "Visual Studio Code": "auto",
            "Messages": "Casual",
            "Notes": "Neutral",
            "Linear": "Professional"
        }
    },
    "ring_buffer": {
        "size": 5,
        "path": "~/.cache/lingopulse/ring.json"
    },
    "history": {
        "path": "~/.config/lingopulse/history.jsonl"
    },
    "tone_overrides": {
        "path": "~/.config/lingopulse/tone_overrides.json"
    }
}

_CONFIG_PATH = pathlib.Path("~/.config/lingopulse/config.json").expanduser()
_cache: dict | None = None


def _deep_merge(base: dict, override: dict) -> dict:
    result = dict(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def get() -> dict:
    global _cache
    if _cache is not None:
        return _cache

    if not _CONFIG_PATH.exists():
        _CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        _CONFIG_PATH.write_text(json.dumps(DEFAULTS, indent=2))
        _cache = dict(DEFAULTS)
        return _cache

    user_config = json.loads(_CONFIG_PATH.read_text())
    _cache = _deep_merge(DEFAULTS, user_config)
    return _cache


def reload() -> dict:
    global _cache
    _cache = None
    return get()


def path_for(key_dotpath: str) -> pathlib.Path:
    cfg = get()
    parts = key_dotpath.split(".")
    value = cfg
    for part in parts:
        value = value[part]
    return pathlib.Path(str(value)).expanduser()
