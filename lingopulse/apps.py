import subprocess
import time

from . import clipboard

_frontmost_cache: tuple[float, str] | None = None
_CACHE_TTL = 0.1


def frontmost() -> str:
    global _frontmost_cache
    now = time.monotonic()
    if _frontmost_cache is not None and (now - _frontmost_cache[0]) < _CACHE_TTL:
        return _frontmost_cache[1]

    result = subprocess.run(
        [
            "osascript",
            "-e",
            'tell application "System Events" to name of first application process whose frontmost is true',
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    name = result.stdout.strip()
    _frontmost_cache = (now, name)
    return name


def copy_selection() -> str:
    subprocess.run(
        ["osascript", "-e", 'tell application "System Events" to keystroke "c" using command down'],
        check=True,
    )
    time.sleep(0.05)
    return clipboard.paste()


def paste_text(text: str) -> None:
    clipboard.copy(text)
    subprocess.run(
        ["osascript", "-e", 'tell application "System Events" to keystroke "v" using command down'],
        check=True,
    )
