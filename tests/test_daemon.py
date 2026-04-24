import json
import pathlib
import threading
import time
import unittest.mock as mock
import urllib.request
from http.server import ThreadingHTTPServer

import pytest

import lingopulse.config as config_mod
import lingopulse.ollama_client as ollama_mod
from lingopulse.daemon import Handler
from lingopulse.ollama_client import InferenceBusyError, OllamaTimeoutError


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def reset_ollama_lock():
    if ollama_mod._lock.locked():
        ollama_mod._lock.release()
    yield
    if ollama_mod._lock.locked():
        ollama_mod._lock.release()


@pytest.fixture()
def tmp_config(tmp_path, monkeypatch):
    """Redirect config, history, and ring-buffer paths to tmp_path."""
    cfg_path = tmp_path / "config.json"
    ring_path = tmp_path / "ring.json"
    history_path = tmp_path / "history.jsonl"

    config = dict(config_mod.DEFAULTS)
    config["ring_buffer"] = {"size": 5, "path": str(ring_path)}
    config["history"] = {"path": str(history_path)}
    config["daemon"] = {"port": 0}

    cfg_path.write_text(json.dumps(config))

    monkeypatch.setattr(config_mod, "_CONFIG_PATH", cfg_path)
    monkeypatch.setattr(config_mod, "_cache", None)

    yield config_mod.get()

    monkeypatch.setattr(config_mod, "_cache", None)


@pytest.fixture()
def server(tmp_config):
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    t = threading.Thread(target=srv.serve_forever)
    t.daemon = True
    t.start()
    yield srv
    srv.shutdown()
    t.join()


def _url(server, path: str) -> str:
    port = server.server_address[1]
    return f"http://127.0.0.1:{port}{path}"


def _get(server, path: str):
    req = urllib.request.Request(_url(server, path))
    with urllib.request.urlopen(req, timeout=5) as resp:
        return resp.status, json.loads(resp.read())


def _post(server, path: str, body: dict, expect_error: bool = False):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        _url(server, path),
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read())


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_status_returns_expected_shape(server):
    with mock.patch("lingopulse.daemon._probe_ollama_ps", return_value=(True, True)):
        status, body = _get(server, "/status")

    assert status == 200
    assert body["ok"] is True
    data = body["data"]
    assert "healthy" in data
    assert "model" in data
    assert "model_loaded" in data
    assert data["healthy"] is True
    assert data["model_loaded"] is True


def test_config_returns_top_level_keys(server):
    status, body = _get(server, "/config")
    assert status == 200
    assert body["ok"] is True
    data = body["data"]
    for key in ("fixer", "dictionary", "keepalive", "ring_buffer", "history", "daemon"):
        assert key in data, f"missing key: {key}"


def test_refine_happy_path(server, tmp_path):
    with mock.patch("lingopulse.ollama_client.OllamaClient.generate", return_value="Hello world refined"):
        status, body = _post(server, "/refine", {"selection": "Hello world", "app": "Slack"})

    assert status == 200
    assert body["ok"] is True
    data = body["data"]
    assert data["original"] == "Hello world"
    assert "refined" in data
    assert "diff" in data
    assert "ring_id" in data


def test_refine_missing_fields_returns_400(server):
    status, body = _post(server, "/refine", {"selection": "text"})
    assert status == 400
    assert body["ok"] is False


def test_refine_undo_returns_original(server):
    with mock.patch("lingopulse.ollama_client.OllamaClient.generate", return_value="Polished text"):
        _post(server, "/refine", {"selection": "Original text", "app": "Mail"})

    status, body = _post(server, "/refine/undo", {})
    assert status == 200
    assert body["ok"] is True
    assert body["data"]["original"] == "Original text"


def test_dictionary_english_path(server):
    candidates = [
        {"word": "ephemeral", "example": "The joy was ephemeral.", "register": "formal"},
        {"word": "fleeting", "example": "A fleeting moment.", "register": "neutral"},
        {"word": "transient", "example": "Transient pleasures.", "register": "formal"},
    ]
    with mock.patch("lingopulse.ollama_client.OllamaClient.generate", return_value=json.dumps(candidates)):
        status, body = _post(server, "/dictionary", {"query": "fleeting"})

    assert status == 200
    assert body["ok"] is True
    assert body["data"]["query_language"] == "english"
    assert isinstance(body["data"]["candidates"], list)


def test_dictionary_hebrew_path(server):
    candidates = [
        {"word": "ephemeral", "example": "...", "register": "formal", "confidence": "high"},
    ]
    with mock.patch("lingopulse.ollama_client.OllamaClient.generate", return_value=json.dumps(candidates)):
        status, body = _post(server, "/dictionary", {"query": "מילה חולפת"})

    assert status == 200
    assert body["ok"] is True
    assert body["data"]["query_language"] == "hebrew"


def test_dictionary_pick_logs_and_returns_word(server, tmp_path):
    candidates = [
        {"word": "ephemeral", "example": "...", "register": "formal"},
        {"word": "fleeting", "example": "...", "register": "neutral"},
    ]
    status, body = _post(server, "/dictionary/pick", {
        "query": "passing quickly",
        "candidates": candidates,
        "picked_index": 1,
        "app": "Slack",
    })
    assert status == 200
    assert body["ok"] is True
    assert body["data"]["picked_word"] == "fleeting"


def test_capture_style_logs_entry(server):
    status, body = _post(server, "/capture_style", {"text": "Write with clarity.", "app": "Notes"})
    assert status == 200
    assert body["ok"] is True
    assert body["data"]["saved"] is True


def test_inference_busy_returns_409(server):
    with mock.patch("lingopulse.fixer.OllamaClient") as MockClient:
        MockClient.return_value.generate.side_effect = InferenceBusyError("busy")
        status, body = _post(server, "/refine", {"selection": "hello", "app": "Slack"})

    assert status == 409
    assert body["ok"] is False
    assert "busy" in body["error"]


def test_ollama_timeout_returns_504(server):
    with mock.patch("lingopulse.fixer.OllamaClient") as MockClient:
        MockClient.return_value.generate.side_effect = OllamaTimeoutError("timeout")
        status, body = _post(server, "/refine", {"selection": "hello", "app": "Slack"})

    assert status == 504
    assert body["ok"] is False


def test_malformed_json_body_returns_400(server):
    port = server.server_address[1]
    url = f"http://127.0.0.1:{port}/refine"
    req = urllib.request.Request(
        url,
        data=b"not valid json",
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.status
            body = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        status = exc.code
        body = json.loads(exc.read())

    assert status == 400
    assert body["ok"] is False
