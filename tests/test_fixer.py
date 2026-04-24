import pathlib
import unittest.mock as mock

import pytest

import lingopulse.gec as gec_mod
import lingopulse.fixer as fixer_mod
from lingopulse.fixer import refine
from lingopulse.gec import GecError


@pytest.fixture()
def base_config(tmp_path):
    return {
        "fixer": {"model": "gemma3:1b-it-qat", "timeout_seconds": 5},
        "keepalive": {"ollama_keep_alive": "30m"},
        "ring_buffer": {"size": 5, "path": str(tmp_path / "ring.json")},
        "history": {"path": str(tmp_path / "history.jsonl")},
        "pipeline": {
            "gec_enabled": True,
            "gec_max_length": 512,
            "tone_classifier_enabled": True,
            "fallback_to_llm_if_gec_fails": True,
        },
    }


@pytest.fixture()
def mock_llm():
    with mock.patch("lingopulse.fixer.OllamaClient") as cls:
        instance = cls.return_value
        instance.generate.return_value = "LLM output"
        yield instance


@pytest.fixture()
def mock_gec_correct():
    with mock.patch("lingopulse.fixer.gec.correct", return_value="GEC output") as m:
        yield m


@pytest.fixture()
def mock_tone_no_shift():
    with mock.patch(
        "lingopulse.fixer.tone.needs_shift", return_value=(False, "Neutral")
    ) as m:
        yield m


@pytest.fixture()
def mock_tone_shift():
    with mock.patch(
        "lingopulse.fixer.tone.needs_shift", return_value=(True, "Professional")
    ) as m:
        yield m


# --- GEC-only path ---

def test_gec_only_no_llm(base_config, mock_gec_correct, mock_tone_no_shift):
    """When GEC succeeds and no tone shift needed, LLM is not called."""
    with mock.patch("lingopulse.fixer.OllamaClient") as llm_cls:
        result = refine("your wrong", "Slack", base_config)

    assert result["gec_used"] is True
    assert result["llm_used"] is False
    llm_cls.assert_not_called()
    assert result["refined"] == "GEC output"
    assert result["original"] == "your wrong"
    assert result["app"] == "Slack"


# --- GEC + LLM path (tone shift forced) ---

def test_gec_then_llm_when_tone_shift_needed(base_config, mock_gec_correct, mock_tone_shift, mock_llm):
    result = refine("your wrong", "Mail", base_config)

    assert result["gec_used"] is True
    assert result["llm_used"] is True
    mock_llm.generate.assert_called_once()
    assert result["refined"] == "LLM output"


def test_gec_then_llm_when_tone_override_given(base_config, mock_gec_correct, mock_llm):
    with mock.patch(
        "lingopulse.fixer.tone.needs_shift", return_value=(True, "Professional")
    ):
        result = refine("your wrong", "Slack", base_config, tone_override="Professional")

    assert result["gec_used"] is True
    assert result["llm_used"] is True


# --- GEC fallback path ---

def test_gec_error_falls_back_to_llm(base_config, mock_tone_shift, mock_llm):
    with mock.patch("lingopulse.fixer.gec.correct", side_effect=GecError("model fail")):
        result = refine("your wrong", "Mail", base_config)

    assert result["gec_used"] is False
    assert result["llm_used"] is True
    mock_llm.generate.assert_called_once()


def test_gec_error_no_fallback_raises(base_config, mock_tone_shift):
    base_config["pipeline"]["fallback_to_llm_if_gec_fails"] = False
    with mock.patch("lingopulse.fixer.gec.correct", side_effect=GecError("boom")):
        with pytest.raises(GecError):
            refine("your wrong", "Mail", base_config)


# --- gec_enabled=False path ---

def test_gec_disabled_skips_gec_calls_llm(base_config, mock_tone_no_shift, mock_llm):
    base_config["pipeline"]["gec_enabled"] = False
    with mock.patch("lingopulse.fixer.gec.correct") as gec_mock:
        result = refine("your wrong", "Slack", base_config)

    gec_mock.assert_not_called()
    assert result["gec_used"] is False
    assert result["llm_used"] is True


# --- Hebrew input path ---

def test_hebrew_gec_skipped_no_tone_shift(base_config, mock_llm):
    hebrew_text = "שלום, מה שלומך?"
    with mock.patch("lingopulse.fixer.gec.correct", return_value=hebrew_text) as gec_mock, \
         mock.patch("lingopulse.fixer.tone.needs_shift", return_value=(False, "hebrew")):
        result = refine(hebrew_text, "Slack", base_config)

    assert result["llm_used"] is False
    mock_llm.generate.assert_not_called()


def test_hebrew_llm_called_when_override(base_config, mock_llm):
    hebrew_text = "שלום, מה שלומך?"
    # tone_override forces shift even for Hebrew — tone.needs_shift detects hebrew first
    # but if override is set, needs_shift returns (False, "hebrew") because Hebrew never shifts
    with mock.patch("lingopulse.fixer.gec.correct", return_value=hebrew_text), \
         mock.patch("lingopulse.fixer.tone.needs_shift", return_value=(False, "hebrew")):
        result = refine(hebrew_text, "Slack", base_config, tone_override="Professional")

    # Hebrew: needs_shift returns False — LLM skipped since GEC ran fine
    assert result["gec_used"] is True
    assert result["llm_used"] is False


# --- tone_classifier_enabled=False ---

def test_tone_disabled_always_calls_llm(base_config, mock_gec_correct, mock_llm):
    base_config["pipeline"]["tone_classifier_enabled"] = False
    result = refine("your wrong", "Slack", base_config)

    assert result["llm_used"] is True


# --- empty selection ---

def test_empty_selection_raises(base_config):
    with pytest.raises(ValueError, match="Empty selection"):
        refine("   ", "Slack", base_config)


# --- backward compat: result has original, refined, app ---

def test_result_keys(base_config, mock_gec_correct, mock_tone_no_shift):
    with mock.patch("lingopulse.fixer.OllamaClient"):
        result = refine("hello world", "Notes", base_config)

    assert "original" in result
    assert "refined" in result
    assert "app" in result
