import json
import threading
import urllib.error
import urllib.request
from typing import Callable


class OllamaError(Exception):
    pass


class InferenceBusyError(OllamaError):
    pass


class OllamaTimeoutError(OllamaError):
    pass


_lock = threading.Lock()


class OllamaClient:
    def __init__(self, host: str = "http://127.0.0.1:11434"):
        self._host = host

    def generate(
        self,
        *,
        model: str,
        prompt: str,
        keep_alive: str = "30m",
        format: str | None = None,
        timeout: float = 15.0,
        on_started: Callable[[], None] | None = None,
        on_complete: Callable[[str], None] | None = None,
    ) -> str:
        acquired = _lock.acquire(blocking=False)
        if not acquired:
            raise InferenceBusyError("Inference already in progress")
        try:
            payload: dict = {
                "model": model,
                "prompt": prompt,
                "keep_alive": keep_alive,
                "stream": False,
            }
            if format is not None:
                payload["format"] = format

            data = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(
                f"{self._host}/api/generate",
                data=data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )

            if on_started is not None:
                on_started()

            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    body = resp.read()
            except TimeoutError as exc:
                raise OllamaTimeoutError("Request timed out") from exc
            except urllib.error.URLError as exc:
                if isinstance(exc.reason, TimeoutError):
                    raise OllamaTimeoutError("Request timed out") from exc
                raise OllamaError(str(exc)) from exc

            result = json.loads(body)
            response_text: str = result["response"]

            if on_complete is not None:
                on_complete(response_text)

            return response_text
        finally:
            _lock.release()
