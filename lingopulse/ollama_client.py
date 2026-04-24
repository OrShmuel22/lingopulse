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


def _load_backend() -> tuple[str, str]:
    from lingopulse import config as _config
    cfg = _config.get()
    backend = cfg.get("backend", {})
    return backend.get("type", "ollama"), backend.get("host", "http://127.0.0.1:11434")


class OllamaClient:
    def __init__(self, host: str | None = None, backend: str | None = None):
        cfg_backend, cfg_host = _load_backend()
        self._backend = backend or cfg_backend
        self._host = host or cfg_host

    def generate(
        self,
        *,
        model: str,
        prompt: str,
        keep_alive: str = "30m",
        format: str | None = None,
        timeout: float = 15.0,
        think: bool = False,
        on_started: Callable[[], None] | None = None,
        on_complete: Callable[[str], None] | None = None,
    ) -> str:
        acquired = _lock.acquire(blocking=False)
        if not acquired:
            raise InferenceBusyError("Inference already in progress")
        try:
            if self._backend == "openai":
                url = f"{self._host}/v1/chat/completions"
                payload: dict = {
                    "model": model,
                    "messages": [{"role": "user", "content": prompt}],
                    "stream": False,
                    "max_tokens": 2048,
                }
                if format == "json":
                    payload["response_format"] = {"type": "json_object"}
            else:
                url = f"{self._host}/api/generate"
                payload = {
                    "model": model,
                    "prompt": prompt,
                    "keep_alive": keep_alive,
                    "stream": False,
                    "think": think,
                }
                if format is not None:
                    payload["format"] = format

            data = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(
                url,
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
            if self._backend == "openai":
                response_text: str = result["choices"][0]["message"]["content"]
            else:
                response_text = result["response"]

            if on_complete is not None:
                on_complete(response_text)

            return response_text
        finally:
            _lock.release()
