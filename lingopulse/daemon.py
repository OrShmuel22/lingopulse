import json
import signal
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from lingopulse import config as _config
from lingopulse import dictionary, fixer, history, hud
from lingopulse.ollama_client import (
    InferenceBusyError,
    OllamaClient,
    OllamaError,
    OllamaTimeoutError,
)
from lingopulse.protection import ProtectionError
from lingopulse.ring_buffer import RingBuffer


def _ts() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


def _ring(cfg: dict) -> RingBuffer:
    import pathlib
    path = pathlib.Path(cfg["ring_buffer"]["path"]).expanduser()
    return RingBuffer(path, size=cfg["ring_buffer"]["size"])


def _ok(data) -> bytes:
    return json.dumps({"ok": True, "data": data}, ensure_ascii=False).encode("utf-8")


def _err(msg: str) -> bytes:
    return json.dumps({"ok": False, "error": msg}, ensure_ascii=False).encode("utf-8")


def _probe_ollama_ps(model: str) -> tuple[bool, bool]:
    try:
        req = urllib.request.Request("http://127.0.0.1:11434/api/ps")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read())
            running = [m.get("name", "") for m in data.get("models", [])]
            model_loaded = any(model in name for name in running)
        return True, model_loaded
    except Exception:
        return False, False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[{_ts()}] {self.address_string()} {fmt % args}", flush=True)

    def _read_json(self) -> dict | None:
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return None

    def _send(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        _config.reload()
        cfg = _config.get()
        if self.path == "/status":
            self._handle_status(cfg)
        elif self.path == "/config":
            self._handle_config(cfg)
        else:
            self._send(404, _err("not found"))

    def do_POST(self):
        _config.reload()
        cfg = _config.get()
        body = self._read_json()
        if body is None:
            self._send(400, _err("invalid JSON"))
            return

        if self.path == "/refine":
            self._handle_refine(body, cfg)
        elif self.path == "/refine/undo":
            self._handle_undo(body, cfg)
        elif self.path == "/dictionary":
            self._handle_dictionary(body, cfg)
        elif self.path == "/dictionary/pick":
            self._handle_dictionary_pick(body, cfg)
        elif self.path == "/capture_style":
            self._handle_capture_style(body)
        else:
            self._send(404, _err("not found"))

    def _handle_status(self, cfg: dict) -> None:
        from lingopulse import gec
        model = cfg["fixer"]["model"]
        healthy, model_loaded = _probe_ollama_ps(model)
        gec_enabled = cfg.get("pipeline", {}).get("gec_enabled", True)
        gec_loaded = gec.is_loaded() if gec_enabled else None
        self._send(200, _ok({"healthy": healthy, "model": model, "model_loaded": model_loaded, "gec_loaded": gec_loaded}))

    def _handle_config(self, cfg: dict) -> None:
        self._send(200, _ok(cfg))

    def _handle_refine(self, body: dict, cfg: dict) -> None:
        selection = body.get("selection")
        app = body.get("app")
        if not selection or not app:
            self._send(400, _err("missing selection or app"))
            return
        tone_override = body.get("tone_override")
        try:
            result = fixer.refine(selection, app, cfg, tone_override)
        except InferenceBusyError:
            self._send(409, _err("inference busy"))
            return
        except OllamaTimeoutError:
            self._send(504, _err("ollama timeout"))
            return
        except ProtectionError as exc:
            self._send(422, _err(str(exc)))
            return
        except (OllamaError, Exception) as exc:
            self._send(500, _err(str(exc)))
            return

        ring = _ring(cfg)
        entries = ring.list_all()
        ring_id = entries[0].get("timestamp", "") if entries else ""

        diff = hud.render_diff(result["original"], result["refined"])
        self._send(200, _ok({
            "original": result["original"],
            "refined": result["refined"],
            "diff": diff,
            "ring_id": ring_id,
        }))

    def _handle_undo(self, body: dict, cfg: dict) -> None:
        ring = _ring(cfg)
        entry = ring.pop_latest()
        if entry is None:
            self._send(404, _err("nothing to undo"))
            return
        self._send(200, _ok({"original": entry["original"]}))

    def _handle_dictionary(self, body: dict, cfg: dict) -> None:
        query = body.get("query")
        if not query:
            self._send(400, _err("missing query"))
            return
        is_hebrew = dictionary.detect_hebrew(query)
        prompt = dictionary.build_prompt(query)
        try:
            client = OllamaClient()
            raw = client.generate(
                model=cfg["dictionary"]["model"],
                prompt=prompt,
                format="json",
                timeout=cfg["dictionary"]["timeout_seconds"],
                keep_alive=cfg["keepalive"]["ollama_keep_alive"],
            )
        except InferenceBusyError:
            self._send(409, _err("inference busy"))
            return
        except OllamaTimeoutError:
            self._send(504, _err("ollama timeout"))
            return
        except (OllamaError, Exception) as exc:
            self._send(500, _err(str(exc)))
            return
        candidates = dictionary.parse_response(raw)
        query_language = "hebrew" if is_hebrew else "english"
        self._send(200, _ok({"candidates": candidates, "query_language": query_language}))

    def _handle_dictionary_pick(self, body: dict, cfg: dict) -> None:
        query = body.get("query")
        candidates = body.get("candidates")
        picked_index = body.get("picked_index")
        app = body.get("app", "")
        if query is None or candidates is None or picked_index is None:
            self._send(400, _err("missing query, candidates, or picked_index"))
            return
        try:
            picked_index = int(picked_index)
            picked_word = candidates[picked_index]["word"]
        except (IndexError, KeyError, TypeError, ValueError):
            self._send(400, _err("invalid picked_index or candidates shape"))
            return
        is_hebrew = dictionary.detect_hebrew(query)
        query_language = "hebrew" if is_hebrew else "english"
        history.append({
            "mode": "dictionary",
            "query": query,
            "query_language": query_language,
            "candidates": candidates,
            "picked": picked_word,
            "picked_index": picked_index,
            "app": app,
        })
        self._send(200, _ok({"picked_word": picked_word}))

    def _handle_capture_style(self, body: dict) -> None:
        text = body.get("text")
        app = body.get("app", "")
        if not text:
            self._send(400, _err("missing text"))
            return
        history.append({"mode": "style_example", "text": text, "app": app})
        self._send(200, _ok({"saved": True}))


def _shutdown_handler(server: ThreadingHTTPServer):
    def handle(signum, frame):
        print(f"[{_ts()}] SIGTERM received — shutting down", flush=True)
        server.shutdown()
        sys.exit(0)
    return handle


if __name__ == "__main__":
    cfg = _config.get()
    port = cfg.get("daemon", {}).get("port", 17823)

    if cfg.get("pipeline", {}).get("gec_enabled", True):
        try:
            from lingopulse import gec
            print(f"[{_ts()}] warming GEC model...", flush=True)
            gec.warmup()
            print(f"[{_ts()}] GEC ready.", flush=True)
        except Exception as e:
            print(f"[{_ts()}] WARN: GEC warmup failed ({e}) — fixer will fall back to LLM.", flush=True)

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    signal.signal(signal.SIGTERM, _shutdown_handler(server))
    print(f"[{_ts()}] lingopulse daemon listening on 127.0.0.1:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()
