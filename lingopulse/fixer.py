from datetime import datetime, timezone

from . import gec, history, protection, tone
from .ollama_client import OllamaClient
from .prompts import build_fixer_prompt
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

    Returns dict with keys: original, refined, app, gec_used, llm_used.
    Raises OllamaError subclasses, ProtectionError, or ValueError on bad input.
    """
    if not selection.strip():
        raise ValueError("Empty selection")

    pipeline_cfg = config.get("pipeline", {})

    protected = protection.protect(selection)
    working = protected.redacted

    gec_used = False
    if pipeline_cfg.get("gec_enabled", True):
        try:
            working = gec.correct(
                working,
                max_length=pipeline_cfg.get("gec_max_length", 512),
            )
            gec_used = True
        except gec.GecError:
            if not pipeline_cfg.get("fallback_to_llm_if_gec_fails", True):
                raise

    needs, target_tone = (
        tone.needs_shift(selection, app, tone_override)
        if pipeline_cfg.get("tone_classifier_enabled", True)
        else (True, tone_override or "Neutral")
    )

    llm_used = False
    if needs or not gec_used:
        prompt = build_fixer_prompt(app, target_tone, working)
        client = OllamaClient()
        working = client.generate(
            model=config["fixer"]["model"],
            prompt=prompt,
            keep_alive=config["keepalive"]["ollama_keep_alive"],
            timeout=config["fixer"]["timeout_seconds"],
            think=False,
        )
        llm_used = True

    refined = protection.restore(working, protected.tokens)

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

    return {
        "original": selection,
        "refined": refined,
        "app": app,
        "gec_used": gec_used,
        "llm_used": llm_used,
    }


def already_refined(selection: str, config: dict) -> bool:
    """Return True if selection matches a recently refined entry (within 30s)."""
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
