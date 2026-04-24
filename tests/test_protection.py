import pytest

from lingopulse.protection import ProtectionError, protect, restore


def test_url_roundtrip():
    text = "check out https://example.com/path?q=1 for details"
    protected = protect(text)
    assert "https://" not in protected.redacted
    assert len(protected.tokens) == 1
    restored = restore(protected.redacted, protected.tokens)
    assert restored == text


def test_fenced_code_roundtrip():
    text = "here is code:\n```\ndef foo():\n    pass\n```\nend"
    protected = protect(text)
    assert "```" not in protected.redacted
    restored = restore(protected.redacted, protected.tokens)
    assert restored == text


def test_inline_backtick_roundtrip():
    text = "call `handleClick()` to handle it"
    protected = protect(text)
    assert "`handleClick()`" not in protected.redacted
    restored = restore(protected.redacted, protected.tokens)
    assert restored == text


def test_mixed_content_roundtrip():
    text = (
        "see https://github.com/org/repo and `inline_func()` plus:\n"
        "```\ncode block\n```\nall preserved"
    )
    protected = protect(text)
    assert "https://" not in protected.redacted
    assert "`inline_func()`" not in protected.redacted
    assert "```" not in protected.redacted
    assert len(protected.tokens) == 3
    restored = restore(protected.redacted, protected.tokens)
    assert restored == text


def test_missing_placeholder_raises_protection_error():
    protected = protect("visit https://example.com")
    placeholder = list(protected.tokens.keys())[0]
    tampered = protected.redacted.replace(placeholder, "REMOVED")
    with pytest.raises(ProtectionError):
        restore(tampered, protected.tokens)


def test_different_invocations_generate_different_tokens():
    text = "https://example.com"
    p1 = protect(text)
    p2 = protect(text)
    assert list(p1.tokens.keys())[0] != list(p2.tokens.keys())[0]


def test_no_protected_content_passthrough():
    text = "plain text with no special content"
    protected = protect(text)
    assert protected.redacted == text
    assert protected.tokens == {}
    assert restore(protected.redacted, protected.tokens) == text


def test_fenced_code_takes_priority_over_inline_backtick():
    # A triple-backtick block should be protected as one unit, not split by inline pattern
    text = "```\n`inner` stuff\n```"
    protected = protect(text)
    assert len(protected.tokens) == 1
    restored = restore(protected.redacted, protected.tokens)
    assert restored == text
