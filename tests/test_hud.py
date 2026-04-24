import sys
import unittest.mock as mock

import pytest

from lingopulse.hud import (
    ProgressHandle,
    render_diff,
    show_error,
    show_progress,
    show_toast,
)


def _get_osascript_script(popen_mock):
    args = popen_mock.call_args[0][0]
    assert args[0] == "osascript"
    assert args[1] == "-e"
    return args[2]


def test_show_toast_calls_osascript():
    with mock.patch("subprocess.Popen") as mock_popen:
        show_toast("All done", title="LingoPulse")
    script = _get_osascript_script(mock_popen)
    assert "display notification" in script
    assert "All done" in script
    assert "LingoPulse" in script


def test_show_error_calls_osascript():
    with mock.patch("subprocess.Popen") as mock_popen:
        show_error("Something broke", title="LingoPulse")
    script = _get_osascript_script(mock_popen)
    assert "display notification" in script
    assert "Something broke" in script


def test_show_toast_escapes_double_quotes():
    with mock.patch("subprocess.Popen") as mock_popen:
        show_toast('say "hello"', title="T")
    script = _get_osascript_script(mock_popen)
    assert '\\"hello\\"' in script


def test_show_toast_escapes_backslashes():
    with mock.patch("subprocess.Popen") as mock_popen:
        show_toast("path\\to\\file", title="T")
    script = _get_osascript_script(mock_popen)
    assert "path\\\\to\\\\file" in script


def test_show_progress_returns_handle():
    with mock.patch("subprocess.Popen"):
        handle = show_progress("Working…")
    assert isinstance(handle, ProgressHandle)


def test_progress_handle_update_sends_notification():
    with mock.patch("subprocess.Popen") as mock_popen:
        handle = show_progress("Step 1", title="LingoPulse")
        mock_popen.reset_mock()
        handle.update("Step 2")
    script = _get_osascript_script(mock_popen)
    assert "Step 2" in script
    assert "LingoPulse" in script


def test_progress_handle_close_is_noop():
    with mock.patch("subprocess.Popen"):
        handle = show_progress("…")
    handle.close()  # should not raise


def test_render_diff_simple_replacement():
    result = render_diff("hello world", "hi world")
    assert "~hello~" in result
    assert "**hi**" in result
    assert "world" in result


def test_render_diff_addition():
    result = render_diff("hello", "hello there")
    assert "**there**" in result
    assert "hello" in result


def test_render_diff_deletion():
    result = render_diff("hello world", "hello")
    assert "~world~" in result
    assert "hello" in result


def test_render_diff_identical():
    result = render_diff("same text here", "same text here")
    assert "~" not in result
    assert "**" not in result
    assert "same" in result


def test_render_diff_truncation():
    original = " ".join(["word"] * 50)
    refined = " ".join(["changed"] * 50)
    result = render_diff(original, refined, max_words=10)
    assert "more changes" in result


def test_render_diff_no_truncation_when_within_limit():
    result = render_diff("a b c", "a b d", max_words=40)
    assert "more changes" not in result
