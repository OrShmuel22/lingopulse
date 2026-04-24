import json
import threading
import unittest.mock as mock
import urllib.error
from io import BytesIO

import pytest

import lingopulse.ollama_client as ollama_mod
from lingopulse.ollama_client import (
    InferenceBusyError,
    OllamaClient,
    OllamaTimeoutError,
)


@pytest.fixture(autouse=True)
def reset_lock():
    # Ensure the module-level lock is released before each test
    if ollama_mod._lock.locked():
        ollama_mod._lock.release()
    yield
    if ollama_mod._lock.locked():
        ollama_mod._lock.release()


def _make_response(body: dict):
    data = json.dumps(body).encode("utf-8")
    resp = mock.MagicMock()
    resp.read.return_value = data
    resp.__enter__ = lambda s: s
    resp.__exit__ = mock.MagicMock(return_value=False)
    return resp


def test_generate_returns_response_text():
    client = OllamaClient()
    resp = _make_response({"response": "hello"})
    with mock.patch("urllib.request.urlopen", return_value=resp):
        result = client.generate(model="gemma3:4b", prompt="test")
    assert result == "hello"


def test_generate_request_body_fields():
    client = OllamaClient()
    resp = _make_response({"response": "hello"})
    captured_req = {}

    def fake_urlopen(req, timeout=None):
        captured_req["body"] = json.loads(req.data)
        return resp

    with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
        client.generate(model="my-model", prompt="my-prompt", keep_alive="10m", format="json")

    body = captured_req["body"]
    assert body["model"] == "my-model"
    assert body["prompt"] == "my-prompt"
    assert body["keep_alive"] == "10m"
    assert body["format"] == "json"
    assert body["stream"] is False


def test_generate_no_format_field_when_none():
    client = OllamaClient()
    resp = _make_response({"response": "hello"})
    captured_req = {}

    def fake_urlopen(req, timeout=None):
        captured_req["body"] = json.loads(req.data)
        return resp

    with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
        client.generate(model="m", prompt="p")

    assert "format" not in captured_req["body"]


def test_callbacks_fire_in_order():
    client = OllamaClient()
    resp = _make_response({"response": "done"})
    order = []

    with mock.patch("urllib.request.urlopen", return_value=resp):
        client.generate(
            model="m",
            prompt="p",
            on_started=lambda: order.append("started"),
            on_complete=lambda t: order.append(f"complete:{t}"),
        )

    assert order == ["started", "complete:done"]


def test_on_started_fires_before_http():
    client = OllamaClient()
    resp = _make_response({"response": "ok"})
    call_log = []

    def fake_urlopen(req, timeout=None):
        call_log.append("http")
        return resp

    with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
        client.generate(
            model="m",
            prompt="p",
            on_started=lambda: call_log.append("started"),
        )

    assert call_log == ["started", "http"]


def test_concurrency_second_call_raises_busy():
    client = OllamaClient()
    started = threading.Event()
    release = threading.Event()

    def slow_urlopen(req, timeout=None):
        started.set()
        release.wait()
        return _make_response({"response": "ok"})

    def first_call():
        with mock.patch("urllib.request.urlopen", side_effect=slow_urlopen):
            client.generate(model="m", prompt="p")

    t = threading.Thread(target=first_call)
    t.start()
    started.wait()

    with pytest.raises(InferenceBusyError):
        client.generate(model="m", prompt="p")

    release.set()
    t.join()


def test_timeout_raises_ollama_timeout_error():
    client = OllamaClient()

    def fake_urlopen(req, timeout=None):
        raise TimeoutError("timed out")

    with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
        with pytest.raises(OllamaTimeoutError):
            client.generate(model="m", prompt="p")


def test_url_error_with_timeout_reason_raises_timeout():
    client = OllamaClient()

    def fake_urlopen(req, timeout=None):
        raise urllib.error.URLError(TimeoutError("timed out"))

    with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
        with pytest.raises(OllamaTimeoutError):
            client.generate(model="m", prompt="p")
