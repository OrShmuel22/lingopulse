import subprocess


def copy(text: str) -> None:
    subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)


def paste() -> str:
    return subprocess.check_output(["pbpaste"]).decode("utf-8", errors="replace")


class ClipboardSnapshot:
    def __init__(self):
        self._saved: str = ""

    def __enter__(self) -> "ClipboardSnapshot":
        self._saved = paste()
        return self

    def __exit__(self, *exc) -> None:
        copy(self._saved)
