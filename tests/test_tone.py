import pytest

from lingopulse.tone import detect_register, needs_shift


# --- detect_register ---

def test_detect_hebrew():
    assert detect_register("היי, זה טקסט עברי") == "hebrew"


def test_detect_casual_lowercase_starts():
    # All sentences start lowercase → ratio = 1.0 > 0.5
    text = "hey, how are you? sounds good. let me know."
    assert detect_register(text) == "casual"


def test_detect_formal_long_sentences_with_punct():
    text = (
        "I wanted to follow up on the matter we discussed at length in our previous meeting last Tuesday. "
        "Please find attached the relevant documents for your review and careful consideration at your convenience. "
        "Kindly let me know at your earliest convenience if you require any further information regarding this important issue."
    )
    assert detect_register(text) == "formal"


def test_detect_casual_contractions_short_sentences():
    text = "I'm here. Don't wait. Can't help it."
    assert detect_register(text) == "casual"


def test_detect_neutral_plain():
    text = "The server restarted. Logs are clean. Everything looks fine."
    assert detect_register(text) == "neutral"


def test_detect_neutral_empty_ish():
    assert detect_register("OK") == "neutral"


# --- needs_shift ---

def _cfg_with_app_map(app_map=None, default_tone="Neutral"):
    return {
        "tone": {
            "default_tone": default_tone,
            "app_map": app_map or {},
        }
    }


def test_needs_shift_hebrew_always_false(monkeypatch):
    monkeypatch.setattr("lingopulse.config.get", lambda: _cfg_with_app_map())
    result = needs_shift("שלום עולם", "Slack")
    assert result == (False, "hebrew")


def test_needs_shift_tone_override_differs(monkeypatch):
    monkeypatch.setattr("lingopulse.config.get", lambda: _cfg_with_app_map())
    # casual text + Professional override → shift needed
    flag, target = needs_shift("hey u around?", "Slack", tone_override="Professional")
    assert flag is True
    assert target == "Professional"


def test_needs_shift_tone_override_matches(monkeypatch):
    monkeypatch.setattr("lingopulse.config.get", lambda: _cfg_with_app_map())
    # formal text + formal override → no shift
    text = (
        "I wanted to follow up on the matter we discussed at length in our previous meeting last Tuesday. "
        "Please find attached the relevant documents for your review and careful consideration at your convenience. "
        "Kindly let me know at your earliest convenience if you require any further information regarding this important issue."
    )
    flag, target = needs_shift(text, "Mail", tone_override="formal")
    assert flag is False
    assert target == "formal"


def test_needs_shift_casual_target_casual_no_shift(monkeypatch):
    monkeypatch.setattr(
        "lingopulse.config.get",
        lambda: _cfg_with_app_map(app_map={"Slack": "Casual"}),
    )
    flag, target = needs_shift("hey u around?", "Slack")
    assert flag is False
    assert target == "Casual"


def test_needs_shift_casual_target_professional_shift(monkeypatch):
    monkeypatch.setattr(
        "lingopulse.config.get",
        lambda: _cfg_with_app_map(app_map={"Mail": "Professional"}),
    )
    flag, target = needs_shift("hey u around? lol", "Mail")
    assert flag is True
    assert target == "Professional"


def test_needs_shift_neutral_counts_as_casual_target(monkeypatch):
    # neutral detected, target = Casual → no shift needed (casual ≈ neutral)
    monkeypatch.setattr(
        "lingopulse.config.get",
        lambda: _cfg_with_app_map(app_map={"Slack": "Casual"}),
    )
    text = "The server restarted. Logs are clean. Everything looks fine."
    flag, _ = needs_shift(text, "Slack")
    assert flag is False


def test_needs_shift_auto_app_prose_gives_casual(monkeypatch):
    monkeypatch.setattr(
        "lingopulse.config.get",
        lambda: _cfg_with_app_map(app_map={"Cursor": "auto"}),
    )
    text = "hey can we pair on this bug"
    flag, target = needs_shift(text, "Cursor")
    assert target == "Casual"


def test_needs_shift_default_tone_used_for_unknown_app(monkeypatch):
    monkeypatch.setattr(
        "lingopulse.config.get",
        lambda: _cfg_with_app_map(default_tone="Neutral"),
    )
    text = "The server restarted. Logs are clean. Everything looks fine."
    flag, target = needs_shift(text, "UnknownApp")
    assert target == "Neutral"
