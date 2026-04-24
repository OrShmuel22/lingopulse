#!/Users/orshmuel/Projects/lingopluse/.venv/bin/python
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Refine Selection
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon ✨
# @raycast.packageName LingoPulse
# @raycast.description Context-aware refinement of selected text

import sys
import threading

from lingopulse import apps, config as cfg_mod, history, hud
from lingopulse.clipboard import ClipboardSnapshot
from lingopulse.fixer import already_refined, refine
from lingopulse.ollama_client import InferenceBusyError, OllamaTimeoutError
from lingopulse.protection import ProtectionError


def main():
    config = cfg_mod.get()
    feedback = config["feedback"]

    try:
        with ClipboardSnapshot():
            app = apps.frontmost()
            original = apps.copy_selection()

            if not original.strip():
                hud.show_toast("Nothing selected")
                return

            if already_refined(original, config):
                hud.show_toast("Already refined — press Cmd+Opt+Z to undo")
                return

            progress_handle = None
            stop_event = threading.Event()

            def _hud_thread():
                if stop_event.wait(timeout=feedback["hud_show_after_ms"] / 1000):
                    return
                nonlocal progress_handle
                progress_handle = hud.show_progress("🧠 Refining…")
                if stop_event.wait(
                    timeout=(
                        feedback["hud_cold_start_notice_after_ms"]
                        - feedback["hud_show_after_ms"]
                    )
                    / 1000
                ):
                    return
                if progress_handle:
                    progress_handle.update("Loading model — first use of the session…")
                if stop_event.wait(
                    timeout=(
                        feedback["hud_error_after_ms"]
                        - feedback["hud_cold_start_notice_after_ms"]
                    )
                    / 1000
                ):
                    return
                hud.show_error("Refinement timed out")

            t = threading.Thread(target=_hud_thread, daemon=True)
            t.start()

            try:
                result = refine(original, app, config)
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
