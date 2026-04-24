#!/Users/orshmuel/Projects/lingopluse/.venv/bin/python
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Refine with Tone
# @raycast.mode silent
# @raycast.argument1 { "type": "dropdown", "placeholder": "Tone", "data": [{"title": "Casual", "value": "Casual"}, {"title": "Neutral", "value": "Neutral"}, {"title": "Technical", "value": "Technical"}, {"title": "Professional", "value": "Professional"}, {"title": "Grammar-only", "value": "Grammar-only"}] }
#
# Optional parameters:
# @raycast.icon 🎚️
# @raycast.packageName LingoPulse
# @raycast.description Refine selected text with a specific tone

import json
import pathlib
import sys
import threading

from lingopulse import apps, config as cfg_mod, history, hud
from lingopulse.clipboard import ClipboardSnapshot
from lingopulse.fixer import already_refined, refine
from lingopulse.ollama_client import InferenceBusyError, OllamaTimeoutError
from lingopulse.protection import ProtectionError


def _update_tone_overrides(config: dict, app: str, tone: str) -> None:
    overrides_path = pathlib.Path(
        config["tone_overrides"]["path"]
    ).expanduser()
    overrides_path.parent.mkdir(parents=True, exist_ok=True)

    overrides: dict = {}
    if overrides_path.exists():
        try:
            overrides = json.loads(overrides_path.read_text())
        except (json.JSONDecodeError, OSError):
            overrides = {}

    overrides[app] = tone
    overrides_path.write_text(json.dumps(overrides, indent=2, ensure_ascii=False))


def main():
    if len(sys.argv) < 2:
        hud.show_error("No tone argument provided")
        sys.exit(1)

    tone = sys.argv[1]
    config = cfg_mod.get()
    feedback = config["feedback"]

    try:
        with ClipboardSnapshot():
            app = apps.frontmost()
            original = apps.copy_selection()

            if not original.strip():
                hud.show_toast("Nothing selected")
                return

            _update_tone_overrides(config, app, tone)

            stop_event = threading.Event()

            def _hud_thread():
                if stop_event.wait(timeout=feedback["hud_show_after_ms"] / 1000):
                    return
                handle = hud.show_progress(f"🧠 Refining ({tone})…")
                if stop_event.wait(
                    timeout=(
                        feedback["hud_cold_start_notice_after_ms"]
                        - feedback["hud_show_after_ms"]
                    )
                    / 1000
                ):
                    return
                handle.update("Loading model — first use of the session…")

            t = threading.Thread(target=_hud_thread, daemon=True)
            t.start()

            try:
                result = refine(original, app, config, tone_override=tone)
            except InferenceBusyError:
                stop_event.set()
                hud.show_toast("Already refining — wait for the current refinement")
                return
            except OllamaTimeoutError:
                stop_event.set()
                hud.show_error("Refinement timed out")
                return
            except ProtectionError:
                stop_event.set()
                hud.show_error(
                    "Refinement returned unexpected output — original preserved"
                )
                return

            stop_event.set()

            apps.paste_text(result["refined"])
            diff = hud.render_diff(original, result["refined"])
            hud.show_toast(
                diff + " · ⌘⌥Z to undo",
                duration_s=feedback["toast_duration_seconds"],
            )

    except Exception as e:
        hud.show_error(str(e))
        raise


if __name__ == "__main__":
    main()
