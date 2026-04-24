import pytest

from lingopulse.dictionary import (
    DICTIONARY_EN_PROMPT,
    DICTIONARY_HE_PROMPT,
    build_prompt,
    detect_hebrew,
    parse_response,
    render_candidates,
)


# --- detect_hebrew ---

def test_detect_hebrew_with_hebrew_text():
    assert detect_hebrew("להפעיל מחדש שרת") is True


def test_detect_hebrew_with_mixed_text():
    assert detect_hebrew("restart the שרת") is True


def test_detect_hebrew_with_english_only():
    assert detect_hebrew("restart the server") is False


def test_detect_hebrew_empty_string():
    assert detect_hebrew("") is False


def test_detect_hebrew_numbers_and_punct():
    assert detect_hebrew("123 !@#$%") is False


# --- build_prompt ---

def test_build_prompt_english_query():
    prompt = build_prompt("restart the server gracefully")
    assert "{query}" not in prompt
    assert "restart the server gracefully" in prompt
    assert "JSON array" in prompt


def test_build_prompt_hebrew_query():
    prompt = build_prompt("להפעיל מחדש")
    assert "Hebrew" in prompt
    assert "להפעיל מחדש" in prompt
    assert "confidence" in prompt


def test_build_prompt_selects_correct_template_for_english():
    prompt = build_prompt("the word for when something breaks quietly")
    # English template does not mention "Hebrew speaker"
    assert "Hebrew speaker" not in prompt


def test_build_prompt_selects_hebrew_template_for_hebrew():
    prompt = build_prompt("מילה לתחושת עייפות")
    assert "Hebrew speaker" in prompt


# --- parse_response ---

def test_parse_response_clean_json():
    raw = '[{"word": "restart", "example": "Restart the server.", "register": "neutral"}]'
    result = parse_response(raw)
    assert len(result) == 1
    assert result[0]["word"] == "restart"


def test_parse_response_strips_markdown_fences():
    raw = '```json\n[{"word": "reboot", "example": "Reboot it.", "register": "casual"}]\n```'
    result = parse_response(raw)
    assert len(result) == 1
    assert result[0]["word"] == "reboot"


def test_parse_response_with_preamble():
    raw = 'Here are the candidates:\n[{"word": "cycle", "example": "Cycle the service.", "register": "technical"}]'
    result = parse_response(raw)
    assert len(result) == 1
    assert result[0]["word"] == "cycle"


def test_parse_response_multiple_candidates():
    raw = '[{"word": "restart", "example": "A.", "register": "neutral"}, {"word": "reboot", "example": "B.", "register": "casual"}]'
    result = parse_response(raw)
    assert len(result) == 2


def test_parse_response_with_confidence_field():
    raw = '[{"word": "reinitialize", "example": "X.", "register": "formal", "confidence": "low"}]'
    result = parse_response(raw)
    assert result[0]["confidence"] == "low"


def test_parse_response_empty_returns_empty_list():
    result = parse_response("")
    assert result == []


def test_parse_response_invalid_json_falls_back_to_empty():
    result = parse_response("not json at all {{{")
    assert isinstance(result, list)


def test_parse_response_regex_fallback_extracts_objects():
    # Malformed outer array but valid individual objects
    raw = 'Some text {"word": "pause", "example": "Pause it.", "register": "neutral"} more text'
    result = parse_response(raw)
    assert len(result) == 1
    assert result[0]["word"] == "pause"


# --- render_candidates ---

def test_render_candidates_basic():
    candidates = [
        {"word": "restart", "example": "Restart the server.", "register": "neutral"},
    ]
    output = render_candidates(candidates)
    assert "1. restart [neutral]" in output
    assert '"Restart the server."' in output


def test_render_candidates_low_confidence_flag():
    candidates = [
        {"word": "reboot", "example": "Reboot it.", "register": "casual", "confidence": "low"},
    ]
    output = render_candidates(candidates)
    assert "⚠️ low confidence" in output


def test_render_candidates_high_confidence_no_flag():
    candidates = [
        {"word": "cycle", "example": "Cycle it.", "register": "technical", "confidence": "high"},
    ]
    output = render_candidates(candidates)
    assert "⚠️" not in output


def test_render_candidates_multiple():
    candidates = [
        {"word": "restart", "example": "A.", "register": "neutral"},
        {"word": "reboot", "example": "B.", "register": "casual"},
        {"word": "reinitialize", "example": "C.", "register": "formal"},
    ]
    output = render_candidates(candidates)
    assert "1. restart" in output
    assert "2. reboot" in output
    assert "3. reinitialize" in output
