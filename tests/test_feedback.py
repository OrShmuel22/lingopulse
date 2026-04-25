import pytest

import lingopulse.config as config_mod
import lingopulse.feedback as fb_mod


@pytest.fixture(autouse=True)
def reset_config_cache():
    config_mod._cache = None
    yield
    config_mod._cache = None


@pytest.fixture()
def feedback_path(tmp_path, monkeypatch):
    config_path = tmp_path / "config.json"
    fb_file = tmp_path / "feedback.jsonl"
    monkeypatch.setattr(config_mod, "_CONFIG_PATH", config_path)
    config_mod._cache = {
        **config_mod.DEFAULTS,
        "feedback": {**config_mod.DEFAULTS["feedback"], "path": str(fb_file)},
    }
    return fb_file


def test_append_persists_full_entry(feedback_path):
    fb_mod.append(
        input_text="hello world",
        rejected_output="Hello, world.",
        reason="too_formal",
        app="Slack",
        tone="Casual",
        note="custom comment",
    )
    entries = fb_mod.read_all()
    assert len(entries) == 1
    e = entries[0]
    assert e["input"] == "hello world"
    assert e["reason"] == "too_formal"
    assert e["app"] == "Slack"
    assert e["note"] == "custom comment"
    assert "timestamp" in e


def test_append_rejects_invalid_reason(feedback_path):
    with pytest.raises(ValueError):
        fb_mod.append(
            input_text="x",
            rejected_output="y",
            reason="not_a_real_reason",
        )


def test_round_trip_preserves_order(feedback_path):
    fb_mod.append(input_text="a", rejected_output="A", reason="too_formal", app="Slack")
    fb_mod.append(input_text="b", rejected_output="B", reason="lost_voice", app="Mail")
    entries = fb_mod.read_all()
    assert [e["app"] for e in entries] == ["Slack", "Mail"]
