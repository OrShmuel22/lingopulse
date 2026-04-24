#!/Users/orshmuel/Projects/lingopluse/.venv/bin/python
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Refine Selection (Preview)
# @raycast.mode fullOutput
#
# Optional parameters:
# @raycast.icon 🔍
# @raycast.packageName LingoPulse
# @raycast.description Refine and show diff — apply immediately, undo with Cmd+Opt+Z

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
                print("Nothing selected.")
                return

            if already_refined(original, config):
                print("Already refined — press Cmd+Opt+Z to undo if needed.")
                return

            stop_event = threading.Event()

            def _hud_thread():
                if stop_event.wait(timeout=feedback["hud_show_after_ms"] / 1000):
                    return
                handle = hud.show_progress("🧠 Refining…")
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
                result = refine(original, app, config)
            except InferenceBusyError:
                stop_event.set()
                print("Already refining — wait for the current refinement to finish.")
                return
            except OllamaTimeoutError:
                stop_event.set()
                print("Refinement timed out.")
                return
            except ProtectionError:
                stop_event.set()
                print("Refinement returned unexpected output — original preserved.")
                return

            stop_event.set()

            apps.paste_text(result["refined"])

            diff = hud.render_diff(original, result["refined"])
            print("=== Diff ===")
            print(diff)
            print()
            print("--- Refined ---")
            print(result["refined"])
            print()
            print("Applied immediately. Press Cmd+Opt+Z to undo.")

            history.append(
                {
                    "mode": "fixer_preview",
                    "app": app,
                    "original": original,
                    "refined": result["refined"],
                }
            )

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        hud.show_error(str(e))
        raise


if __name__ == "__main__":
    main()
