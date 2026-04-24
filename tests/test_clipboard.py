import sys

import pytest

pytestmark = pytest.mark.skipif(sys.platform != "darwin", reason="macOS only")

from lingopulse.clipboard import ClipboardSnapshot, copy, paste


def test_copy_paste_roundtrip():
    copy("hello lingopulse")
    assert paste() == "hello lingopulse"


def test_copy_paste_unicode():
    copy("שלום עולם")
    assert paste() == "שלום עולם"


def test_snapshot_preserves_pre_existing_value():
    copy("original value")
    with ClipboardSnapshot():
        copy("temporary value")
        assert paste() == "temporary value"
    assert paste() == "original value"


def test_snapshot_restores_on_exception():
    copy("safe value")
    try:
        with ClipboardSnapshot():
            copy("changed during work")
            raise RuntimeError("something went wrong")
    except RuntimeError:
        pass
    assert paste() == "safe value"
