#!/Users/orshmuel/Projects/lingopluse/.venv/bin/python
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Save as Style Example
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 📝
# @raycast.packageName LingoPulse
# @raycast.description Save the current selection as a style example for future training

from lingopulse import apps, history, hud
from lingopulse.clipboard import ClipboardSnapshot


def main():
    with ClipboardSnapshot():
        text = apps.copy_selection()

    if not text.strip():
        hud.show_toast("Nothing selected")
        return

    app = apps.frontmost()
    history.append({"mode": "style_example", "text": text, "app": app})
    hud.show_toast("Saved as style example")


if __name__ == "__main__":
    main()
