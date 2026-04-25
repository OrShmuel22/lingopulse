import pytest

import lingopulse.config as config_mod
import lingopulse.personal_dict as pd_mod


@pytest.fixture(autouse=True)
def reset_config_cache():
    config_mod._cache = None
    yield
    config_mod._cache = None


@pytest.fixture()
def dict_path(tmp_path, monkeypatch):
    config_path = tmp_path / "config.json"
    pd_file = tmp_path / "personal_dict.json"
    monkeypatch.setattr(config_mod, "_CONFIG_PATH", config_path)
    config_mod._cache = {
        **config_mod.DEFAULTS,
        "personal_dict": {"path": str(pd_file)},
    }
    return pd_file


def test_add_persists_and_lists(dict_path):
    entry = pd_mod.add("Yossi")
    assert entry["scope"] == "*"
    assert pd_mod.list_all() == [entry]


def test_add_dedupes_same_token_and_scope(dict_path):
    pd_mod.add("Yossi", scope="Slack")
    pd_mod.add("Yossi", scope="Slack")
    assert len(pd_mod.list_all()) == 1


def test_add_allows_same_token_different_scope(dict_path):
    pd_mod.add("Yossi", scope="*")
    pd_mod.add("Yossi", scope="Slack")
    assert len(pd_mod.list_all()) == 2


def test_remove_by_token_only_clears_all_scopes(dict_path):
    pd_mod.add("foo", scope="*")
    pd_mod.add("foo", scope="Slack")
    pd_mod.add("bar", scope="*")
    removed = pd_mod.remove("foo")
    assert removed == 2
    remaining = [t["token"] for t in pd_mod.list_all()]
    assert remaining == ["bar"]


def test_remove_by_token_and_scope_keeps_other_scopes(dict_path):
    pd_mod.add("foo", scope="*")
    pd_mod.add("foo", scope="Slack")
    pd_mod.remove("foo", scope="Slack")
    remaining = pd_mod.list_all()
    assert len(remaining) == 1
    assert remaining[0]["scope"] == "*"


def test_tokens_for_app_includes_wildcard_and_scope_match(dict_path):
    pd_mod.add("global_term", scope="*")
    pd_mod.add("slack_term", scope="Slack")
    pd_mod.add("mail_term", scope="Mail")
    assert sorted(pd_mod.tokens_for_app("Slack")) == ["global_term", "slack_term"]
    assert pd_mod.tokens_for_app("Other") == ["global_term"]
