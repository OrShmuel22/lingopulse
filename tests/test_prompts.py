import pytest

from lingopulse.prompts import (
    TONE_DESCRIPTIONS,
    build_fixer_prompt,
    classify_selection,
    tone_for_app,
)


# --- classify_selection ---

def test_classify_triple_backtick_fence():
    text = "here is some code:\n```\ndef foo(): pass\n```"
    assert classify_selection(text) == "code"


def test_classify_code_char_ratio_above_threshold():
    # lots of brackets/semicolons/equals
    text = "if (x > 0) { return x; } else { return -x; }"
    assert classify_selection(text) == "code"


def test_classify_comment_marker_slash_slash():
    text = "// This is a comment\nsome more text"
    assert classify_selection(text) == "code"


def test_classify_comment_marker_hash():
    text = "# Python comment\nprint('hello')"
    assert classify_selection(text) == "code"


def test_classify_comment_marker_block():
    text = "/* block comment */\nint x = 0;"
    assert classify_selection(text) == "code"


def test_classify_comment_marker_sql():
    text = "-- SQL comment\nSELECT * FROM users;"
    assert classify_selection(text) == "code"


def test_classify_code_keywords_two_distinct_lines():
    text = "function foo() {\n  return null;\n}"
    assert classify_selection(text) == "code"


def test_classify_one_keyword_line_is_prose():
    # only one distinct line with a keyword — should still be prose
    text = "I want to return to the office tomorrow"
    assert classify_selection(text) == "prose"


def test_classify_prose_plain_sentence():
    text = "Hey, can we schedule a meeting for tomorrow afternoon?"
    assert classify_selection(text) == "prose"


def test_classify_prose_formal_sentence():
    text = "I wanted to flag a compliance concern regarding the recent deployment."
    assert classify_selection(text) == "prose"


def test_classify_code_char_ratio_edge_below_threshold():
    # a sentence with a few punctuation chars but below 15%
    text = "Let me know if (you need anything) else."
    non_ws = len(text.replace(" ", ""))
    code_chars = sum(1 for c in text if c in "{}()[];=<>/|")
    ratio = code_chars / non_ws
    # just verify the test text is indeed below threshold
    assert ratio <= 0.15
    assert classify_selection(text) == "prose"


# --- tone_for_app ---

def _config(app_map=None, default_tone="Neutral"):
    return {
        "tone": {
            "default_tone": default_tone,
            "app_map": app_map or {},
        }
    }


def test_tone_for_app_returns_mapped_value():
    config = _config(app_map={"Slack": "Casual"})
    assert tone_for_app("Slack", "hey there", config) == "Casual"


def test_tone_for_app_falls_back_to_default():
    config = _config(app_map={"Slack": "Casual"}, default_tone="Neutral")
    assert tone_for_app("Firefox", "some text", config) == "Neutral"


def test_tone_for_app_auto_classifies_code_as_technical():
    config = _config(app_map={"Cursor": "auto"})
    code_text = "function foo() {\n  return null;\n}"
    assert tone_for_app("Cursor", code_text, config) == "Technical"


def test_tone_for_app_auto_classifies_prose_as_casual():
    config = _config(app_map={"Cursor": "auto"})
    prose_text = "hey can we pair on this bug"
    assert tone_for_app("Cursor", prose_text, config) == "Casual"


def test_tone_for_app_missing_app_uses_default():
    config = _config(default_tone="Professional")
    assert tone_for_app("Unknown App", "hello", config) == "Professional"


# --- build_fixer_prompt ---

def test_build_fixer_prompt_contains_app_name():
    prompt = build_fixer_prompt("Slack", "Casual", "hey there")
    assert "Slack" in prompt


def test_build_fixer_prompt_contains_tone_name():
    prompt = build_fixer_prompt("Slack", "Casual", "hey there")
    assert "Casual" in prompt


def test_build_fixer_prompt_contains_tone_description():
    prompt = build_fixer_prompt("Slack", "Casual", "hey there")
    assert TONE_DESCRIPTIONS["Casual"] in prompt


def test_build_fixer_prompt_contains_message():
    message = "This is the message body."
    prompt = build_fixer_prompt("Mail", "Professional", message)
    assert message in prompt


def test_build_fixer_prompt_unknown_tone_uses_fallback():
    prompt = build_fixer_prompt("Notes", "UnknownTone", "some text")
    assert "UnknownTone" in prompt
    assert "balanced clarity and grammar" in prompt


def test_build_fixer_prompt_grammar_only_tone():
    prompt = build_fixer_prompt("Mail", "Grammar-only", "fix this plz")
    assert "Grammar-only" in prompt
    assert TONE_DESCRIPTIONS["Grammar-only"] in prompt
