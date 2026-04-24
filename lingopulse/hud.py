import difflib
import subprocess


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def _notify(text: str, title: str) -> None:
    script = f'display notification "{_escape(text)}" with title "{_escape(title)}"'
    subprocess.Popen(["osascript", "-e", script])


def show_toast(text: str, duration_s: float = 5.0, title: str = "LingoPulse") -> None:
    _notify(text, title)


def show_error(text: str, title: str = "LingoPulse") -> None:
    _notify(text, title)


class ProgressHandle:
    def __init__(self, title: str):
        self._title = title

    def update(self, text: str) -> None:
        _notify(text, self._title)

    def close(self) -> None:
        pass


def show_progress(text: str, title: str = "LingoPulse") -> ProgressHandle:
    handle = ProgressHandle(title)
    handle.update(text)
    return handle


def render_diff(original: str, refined: str, max_words: int = 40) -> str:
    orig_words = original.split()
    ref_words = refined.split()

    diff = list(difflib.ndiff(orig_words, ref_words))

    parts: list[str] = []
    word_count = 0
    change_count = 0

    i = 0
    while i < len(diff):
        token = diff[i]
        tag = token[:2]
        word = token[2:]

        if tag == "  ":
            parts.append(word)
            word_count += 1
        elif tag == "- ":
            # check if next is an addition (replacement pair)
            parts.append(f"~{word}~")
            word_count += 1
            change_count += 1
        elif tag == "+ ":
            parts.append(f"**{word}**")
            word_count += 1
            change_count += 1
        # "? " lines from ndiff are hints — skip them

        if word_count >= max_words:
            remaining_changes = sum(
                1 for t in diff[i + 1:] if t[:2] in ("- ", "+ ")
            )
            if remaining_changes > 0:
                parts.append(f"... [+{remaining_changes} more changes]")
            break

        i += 1

    return " ".join(parts)
