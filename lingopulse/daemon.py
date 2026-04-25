import json
import signal
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from lingopulse import config as _config
from lingopulse import dictionary, edits, feedback, fixer, history, hud, personal_dict
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
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)
        if path == "/status":
            self._handle_status(cfg)
        elif path == "/config":
            self._handle_config(cfg)
        elif path == "/history":
            self._handle_history_get(query)
        elif path == "/personal_dict":
            self._handle_personal_dict_get()
        elif path == "/feedback":
            self._handle_feedback_get(query)
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
        elif self.path == "/personal_dict":
            self._handle_personal_dict_add(body)
        elif self.path == "/personal_dict/remove":
            self._handle_personal_dict_remove(body)
        elif self.path == "/feedback":
            self._handle_feedback_post(body)
        elif self.path == "/edits":
            self._handle_edits(body)
        elif self.path == "/apply_edits":
            self._handle_apply_edits(body)
        else:
            self._send(404, _err("not found"))

    def _handle_status(self, cfg: dict) -> None:
        model = cfg["fixer"]["model"]
        healthy, model_loaded = _probe_ollama_ps(model)
        self._send(200, _ok({"healthy": healthy, "model": model, "model_loaded": model_loaded}))

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
        structured_edits = edits.compute_edits(result["original"], result["refined"])
        self._send(200, _ok({
            "original": result["original"],
            "refined": result["refined"],
            "diff": diff,
            "edits": structured_edits,
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

    def _handle_history_get(self, query: dict) -> None:
        limit = int(query.get("limit", ["100"])[0])
        app_filter = query.get("app", [None])[0]
        mode_filter = query.get("mode", [None])[0]
        entries = history.read_all()
        if app_filter:
            entries = [e for e in entries if e.get("app") == app_filter]
        if mode_filter:
            entries = [e for e in entries if e.get("mode") == mode_filter]
        entries = entries[-limit:] if limit > 0 else entries
        self._send(200, _ok({"entries": entries, "total": len(entries)}))

    def _handle_personal_dict_get(self) -> None:
        self._send(200, _ok({"tokens": personal_dict.list_all()}))

    def _handle_personal_dict_add(self, body: dict) -> None:
        token = body.get("token")
        scope = body.get("scope", "*")
        if not token:
            self._send(400, _err("missing token"))
            return
        try:
            entry = personal_dict.add(token, scope)
        except ValueError as exc:
            self._send(400, _err(str(exc)))
            return
        self._send(200, _ok({"entry": entry}))

    def _handle_personal_dict_remove(self, body: dict) -> None:
        token = body.get("token")
        scope = body.get("scope")
        if not token:
            self._send(400, _err("missing token"))
            return
        removed = personal_dict.remove(token, scope)
        self._send(200, _ok({"removed": removed}))

    def _handle_feedback_post(self, body: dict) -> None:
        try:
            entry = feedback.append(
                input_text=body.get("input", ""),
                rejected_output=body.get("rejected_output", ""),
                reason=body.get("reason", ""),
                app=body.get("app", ""),
                tone=body.get("tone", ""),
                note=body.get("note", ""),
            )
        except ValueError as exc:
            self._send(400, _err(str(exc)))
            return
        self._send(200, _ok({"saved": True, "entry": entry}))

    def _handle_edits(self, body: dict) -> None:
        original = body.get("original")
        refined = body.get("refined")
        if original is None or refined is None:
            self._send(400, _err("missing original or refined"))
            return
        result = edits.compute_edits(original, refined)
        self._send(200, _ok({"edits": result, "count": len(result)}))

    def _handle_apply_edits(self, body: dict) -> None:
        original = body.get("original")
        refined = body.get("refined")
        accepted = body.get("accepted_indices")
        if original is None or refined is None or accepted is None:
            self._send(400, _err("missing original, refined, or accepted_indices"))
            return
        if not isinstance(accepted, list):
            self._send(400, _err("accepted_indices must be a list of ints"))
            return
        try:
            accepted_ints = [int(i) for i in accepted]
        except (TypeError, ValueError):
            self._send(400, _err("accepted_indices must contain integers"))
            return
        result = edits.apply_edits(original, refined, accepted_ints)
        self._send(200, _ok({"result": result}))

    def _handle_feedback_get(self, query: dict) -> None:
        limit = int(query.get("limit", ["100"])[0])
        reason_filter = query.get("reason", [None])[0]
        app_filter = query.get("app", [None])[0]
        entries = feedback.read_all()
        if reason_filter:
            entries = [e for e in entries if e.get("reason") == reason_filter]
        if app_filter:
            entries = [e for e in entries if e.get("app") == app_filter]
        entries = entries[-limit:] if limit > 0 else entries
        self._send(200, _ok({"entries": entries, "total": len(entries)}))


def _shutdown_handler(server: ThreadingHTTPServer):
    def handle(signum, frame):
        print(f"[{_ts()}] SIGTERM received — shutting down", flush=True)
        server.shutdown()
        sys.exit(0)
    return handle


if __name__ == "__main__":
    cfg = _config.get()
    port = cfg.get("daemon", {}).get("port", 17823)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    signal.signal(signal.SIGTERM, _shutdown_handler(server))
    print(f"[{_ts()}] lingopulse daemon listening on 127.0.0.1:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()
