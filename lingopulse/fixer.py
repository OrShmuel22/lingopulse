from datetime import datetime, timezone

from . import history, protection
from .ollama_client import OllamaClient
from .prompts import build_fixer_prompt, tone_for_app
from .ring_buffer import RingBuffer


def _iso_now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


def refine(
    selection: str,
    app: str,
    config: dict,
    tone_override: str | None = None,
) -> dict:
    """Run the full fixer pipeline.

    Returns dict with keys: original, refined, app.
    Raises OllamaError subclasses, ProtectionError, or ValueError on bad input.
    """
    if not selection.strip():
        raise ValueError("Empty selection")

    tone = tone_override if tone_override else tone_for_app(app, selection, config)
    protected = protection.protect(selection)
    prompt = build_fixer_prompt(app, tone, protected.redacted)

    client = OllamaClient()
    response = client.generate(
        model=config["fixer"]["model"],
        prompt=prompt,
        keep_alive=config["keepalive"]["ollama_keep_alive"],
        timeout=config["fixer"]["timeout_seconds"],
        options={
            "temperature": 0.1,
            "top_p": 0.9,
            "repeat_penalty": 1.0,
            "stop": ["\nInput:", "\n\n", "\nOutput:"],
        },
    )

    refined = protection.restore(response.strip(), protected.tokens)

    ring_path = _ring_path(config)
    ring = RingBuffer(ring_path, size=config["ring_buffer"]["size"])
    ring.append(
        {
            "original": selection,
            "refined": refined,
            "app": app,
            "timestamp": _iso_now(),
        }
    )

    history.append(
        {
            "mode": "fixer_refine",
            "app": app,
            "original": selection,
            "refined": refined,
        }
    )

    return {"original": selection, "refined": refined, "app": app}


def already_refined(selection: str, config: dict) -> bool:
    """Return True if selection matches a recently refined entry (within 30s)."""
    import time

    ring_path = _ring_path(config)
    ring = RingBuffer(ring_path, size=config["ring_buffer"]["size"])
    entries = ring.list_all()
    now = datetime.now(timezone.utc).astimezone()
    for entry in entries:
        if entry.get("refined") != selection:
            continue
        ts_str = entry.get("timestamp")
        if not ts_str:
            continue
        try:
            ts = datetime.fromisoformat(ts_str)
            if (now - ts).total_seconds() <= 30:
                return True
        except ValueError:
            continue
    return False


def _ring_path(config: dict):
    import pathlib

    return pathlib.Path(config["ring_buffer"]["path"]).expanduser()
