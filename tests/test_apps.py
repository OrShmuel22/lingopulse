import sys
import time
import unittest.mock as mock

import pytest

pytestmark = pytest.mark.skipif(sys.platform != "darwin", reason="macOS only")

import lingopulse.apps as apps_mod
from lingopulse.apps import copy_selection, frontmost, paste_text


@pytest.fixture(autouse=True)
def reset_cache():
    apps_mod._frontmost_cache = None
    yield
    apps_mod._frontmost_cache = None


def test_frontmost_calls_osascript():
    run_result = mock.MagicMock()
    run_result.stdout = "Slack\n"

    with mock.patch("subprocess.run", return_value=run_result) as mock_run:
        name = frontmost()

    assert name == "Slack"
    args = mock_run.call_args[0][0]
    assert args[0] == "osascript"
    assert "frontmost" in args[-1]


def test_frontmost_cache_within_100ms():
    run_result = mock.MagicMock()
    run_result.stdout = "Mail\n"

    with mock.patch("subprocess.run", return_value=run_result) as mock_run:
        frontmost()
        frontmost()

    assert mock_run.call_count == 1


def test_frontmost_cache_expires_after_100ms():
    run_result = mock.MagicMock()
    run_result.stdout = "Notes\n"

    with mock.patch("subprocess.run", return_value=run_result) as mock_run:
        frontmost()
        # Expire the cache by backdating it
        apps_mod._frontmost_cache = (apps_mod._frontmost_cache[0] - 0.2, apps_mod._frontmost_cache[1])
        frontmost()

    assert mock_run.call_count == 2


def test_copy_selection_sends_cmd_c():
    with mock.patch("subprocess.run") as mock_run, \
         mock.patch("lingopulse.apps.clipboard.paste", return_value="selected text"), \
         mock.patch("time.sleep"):
        result = copy_selection()

    assert result == "selected text"
    run_args = mock_run.call_args[0][0]
    assert "osascript" in run_args
    assert any("keystroke" in a and '"c"' in a for a in run_args)


def test_copy_selection_sleeps_before_paste():
    sleep_calls = []

    with mock.patch("subprocess.run"), \
         mock.patch("lingopulse.apps.clipboard.paste", return_value="text"), \
         mock.patch("time.sleep", side_effect=lambda s: sleep_calls.append(s)):
        copy_selection()

    assert len(sleep_calls) == 1
    assert sleep_calls[0] == pytest.approx(0.05)


def test_paste_text_copies_then_sends_cmd_v():
    with mock.patch("lingopulse.apps.clipboard.copy") as mock_copy, \
         mock.patch("subprocess.run") as mock_run:
        paste_text("hello world")

    mock_copy.assert_called_once_with("hello world")
    run_args = mock_run.call_args[0][0]
    assert "osascript" in run_args
    assert any("keystroke" in a and '"v"' in a for a in run_args)
