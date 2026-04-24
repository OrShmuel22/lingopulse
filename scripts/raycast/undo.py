#!/Users/orshmuel/Projects/lingopluse/.venv/bin/python
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Undo Refinement
# @raycast.mode fullOutput
#
# Optional parameters:
# @raycast.icon ↩️
# @raycast.packageName LingoPulse
# @raycast.description Rollback the latest LingoPulse refinement

import pathlib

from lingopulse import apps, config as cfg_mod, history, hud
from lingopulse.clipboard import ClipboardSnapshot
from lingopulse.ring_buffer import RingBuffer


def main():
    config = cfg_mod.get()
    ring_path = pathlib.Path(config["ring_buffer"]["path"]).expanduser()
    ring = RingBuffer(ring_path, size=config["ring_buffer"]["size"])

    entry = ring.pop_latest()
    if entry is None:
        hud.show_toast("Nothing to undo")
        return

    with ClipboardSnapshot():
        current = apps.copy_selection()

    if current == entry["refined"]:
        apps.paste_text(entry["original"])
        hud.show_toast("Reverted — original restored")
        history.append({"mode": "fixer_undo", "app": entry.get("app", "")})
        return

    # Fallback: show last entries as fullOutput panel
    all_entries = ring.list_all()
    # Re-add the popped entry at front since we couldn't use it
    all_entries.insert(0, entry)

    print("Could not locate the refined text in current selection.")
    print("Last refinements (copy manually):\n")
    for i, e in enumerate(all_entries[:5], 1):
        app_label = e.get("app", "unknown")
        ts = e.get("timestamp", "")[:19]
        print(f"--- {i}. [{app_label}] {ts} ---")
        print(e.get("original", ""))
        print()

    history.append({"mode": "fixer_undo_fallback", "app": entry.get("app", "")})


if __name__ == "__main__":
    main()
