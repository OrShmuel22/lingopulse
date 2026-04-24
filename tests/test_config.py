import json
import pathlib
import importlib

import pytest

import lingopulse.config as config_mod


@pytest.fixture(autouse=True)
def reset_cache():
    config_mod._cache = None
    yield
    config_mod._cache = None


@pytest.fixture()
def config_dir(tmp_path, monkeypatch):
    config_path = tmp_path / "config.json"
    monkeypatch.setattr(config_mod, "_CONFIG_PATH", config_path)
    return tmp_path


def test_defaults_created_on_first_call(config_dir):
    cfg = config_mod.get()

    config_path = config_mod._CONFIG_PATH
    assert config_path.exists()
    on_disk = json.loads(config_path.read_text())
    assert on_disk == config_mod.DEFAULTS
    assert cfg == config_mod.DEFAULTS


def test_deep_merge_preserves_user_values(config_dir):
    config_path = config_mod._CONFIG_PATH
    user_override = {
        "fixer": {
            "timeout_seconds": 30
        },
        "keepalive": {
            "ping_interval_minutes": 10
        }
    }
    config_path.write_text(json.dumps(user_override))

    cfg = config_mod.get()

    assert cfg["fixer"]["timeout_seconds"] == 30
    assert cfg["fixer"]["model"] == config_mod.DEFAULTS["fixer"]["model"]
    assert cfg["keepalive"]["ping_interval_minutes"] == 10
    assert cfg["keepalive"]["enabled"] == config_mod.DEFAULTS["keepalive"]["enabled"]


def test_reload_picks_up_changes(config_dir):
    cfg_first = config_mod.get()
    assert cfg_first["fixer"]["timeout_seconds"] == 15

    config_path = config_mod._CONFIG_PATH
    config_path.write_text(json.dumps({"fixer": {"timeout_seconds": 99}}))

    cfg_reloaded = config_mod.reload()
    assert cfg_reloaded["fixer"]["timeout_seconds"] == 99


def test_path_for_expands_tilde(config_dir, monkeypatch):
    config_mod.get()
    p = config_mod.path_for("ring_buffer.path")
    assert isinstance(p, pathlib.Path)
    assert not str(p).startswith("~")
    assert "lingopulse" in str(p)
