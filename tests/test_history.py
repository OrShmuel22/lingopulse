import json
import pathlib

import pytest

import lingopulse.config as config_mod
import lingopulse.history as history_mod


@pytest.fixture(autouse=True)
def reset_config_cache():
    config_mod._cache = None
    yield
    config_mod._cache = None


@pytest.fixture()
def history_path(tmp_path, monkeypatch):
    config_path = tmp_path / "config.json"
    history_file = tmp_path / "history.jsonl"
    monkeypatch.setattr(config_mod, "_CONFIG_PATH", config_path)
    config_mod._cache = {
        **config_mod.DEFAULTS,
        "history": {"path": str(history_file)}
    }
    return history_file


def test_append_and_read_roundtrip(history_path):
    entry = {"mode": "dictionary", "query": "restart", "picked": "reboot"}
    history_mod.append(entry)

    entries = history_mod.read_all()
    assert len(entries) == 1
    assert entries[0]["mode"] == "dictionary"
    assert entries[0]["query"] == "restart"
    assert entries[0]["picked"] == "reboot"


def test_timestamp_auto_added(history_path):
    entry = {"mode": "fixer", "original": "hello wrold"}
    history_mod.append(entry)

    entries = history_mod.read_all()
    assert "timestamp" in entries[0]
    ts = entries[0]["timestamp"]
    assert "T" in ts


def test_existing_timestamp_preserved(history_path):
    ts = "2026-01-01T00:00:00+00:00"
    entry = {"mode": "fixer", "timestamp": ts}
    history_mod.append(entry)

    entries = history_mod.read_all()
    assert entries[0]["timestamp"] == ts


def test_nonexistent_parent_dir(tmp_path, monkeypatch):
    nested_history = tmp_path / "deep" / "nested" / "history.jsonl"
    config_mod._cache = {
        **config_mod.DEFAULTS,
        "history": {"path": str(nested_history)}
    }
    config_path = tmp_path / "config.json"
    monkeypatch.setattr(config_mod, "_CONFIG_PATH", config_path)

    history_mod.append({"mode": "test"})
    assert nested_history.exists()
    entries = history_mod.read_all()
    assert len(entries) == 1


def test_multiple_appends(history_path):
    for i in range(5):
        history_mod.append({"index": i})

    entries = history_mod.read_all()
    assert len(entries) == 5
    assert [e["index"] for e in entries] == list(range(5))


def test_iter_entries_streams(history_path):
    for i in range(3):
        history_mod.append({"n": i})

    streamed = list(history_mod.iter_entries())
    assert len(streamed) == 3


def test_read_all_empty_file(history_path):
    history_path.touch()
    entries = history_mod.read_all()
    assert entries == []


def test_read_all_nonexistent_file(history_path):
    entries = history_mod.read_all()
    assert entries == []
