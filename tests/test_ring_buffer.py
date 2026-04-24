import pathlib

import pytest

from lingopulse.ring_buffer import RingBuffer


def test_append_and_list_all(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    buf.append({"n": 1})
    buf.append({"n": 2})
    entries = buf.list_all()
    assert len(entries) == 2
    assert entries[0]["n"] == 2
    assert entries[1]["n"] == 1


def test_fifo_eviction_at_size_limit(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    for i in range(6):
        buf.append({"n": i})
    entries = buf.list_all()
    assert len(entries) == 5
    ns = [e["n"] for e in entries]
    assert 0 not in ns
    assert sorted(ns) == [1, 2, 3, 4, 5]


def test_pop_latest_roundtrip(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    buf.append({"val": "a"})
    buf.append({"val": "b"})
    popped = buf.pop_latest()
    assert popped == {"val": "b"}
    assert len(buf.list_all()) == 1


def test_pop_latest_empty_returns_none(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    assert buf.pop_latest() is None


def test_persistence_across_reopen(tmp_path):
    path = tmp_path / "ring.json"
    buf1 = RingBuffer(path, size=5)
    buf1.append({"x": 42})
    buf1.append({"x": 99})

    buf2 = RingBuffer(path, size=5)
    entries = buf2.list_all()
    assert len(entries) == 2
    assert entries[0]["x"] == 99


def test_list_all_newest_first(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    for i in range(5):
        buf.append({"n": i})
    entries = buf.list_all()
    ns = [e["n"] for e in entries]
    assert ns == [4, 3, 2, 1, 0]


def test_find_matching_returns_newest_match(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    buf.append({"app": "Mail", "n": 1})
    buf.append({"app": "Slack", "n": 2})
    buf.append({"app": "Mail", "n": 3})

    match = buf.find_matching(lambda e: e["app"] == "Mail")
    assert match["n"] == 3


def test_find_matching_no_match_returns_none(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    buf.append({"app": "Slack"})
    assert buf.find_matching(lambda e: e["app"] == "Mail") is None


def test_auto_creates_parent_dir(tmp_path):
    nested = tmp_path / "a" / "b" / "ring.json"
    buf = RingBuffer(nested, size=5)
    buf.append({"ok": True})
    assert nested.exists()


def test_list_all_empty_returns_empty(tmp_path):
    buf = RingBuffer(tmp_path / "ring.json", size=5)
    assert buf.list_all() == []
