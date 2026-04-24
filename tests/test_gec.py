import unittest.mock as mock

import pytest

import lingopulse.gec as gec_mod
from lingopulse.gec import GecError, GecNotAvailable, correct, warmup


@pytest.fixture(autouse=True)
def reset_gec_cache():
    orig_tokenizer = gec_mod._tokenizer
    orig_model = gec_mod._model
    orig_device = gec_mod._device
    orig_warmed = gec_mod._warmed_up
    yield
    gec_mod._tokenizer = orig_tokenizer
    gec_mod._model = orig_model
    gec_mod._device = orig_device
    gec_mod._warmed_up = orig_warmed


def _install_mock_model(decoded="You're right, should have gone there yesterday."):
    """Patch gec internals with a fake tokenizer + model."""
    import torch

    fake_ids = torch.tensor([[1, 2, 3]])

    encoded = mock.MagicMock()
    encoded.to = mock.MagicMock(return_value=encoded)

    fake_tokenizer = mock.MagicMock()
    fake_tokenizer.return_value = encoded
    fake_tokenizer.decode.return_value = decoded

    fake_model = mock.MagicMock()
    fake_model.generate.return_value = fake_ids
    fake_model.to.return_value = fake_model
    fake_model.eval.return_value = None

    gec_mod._tokenizer = fake_tokenizer
    gec_mod._model = fake_model
    gec_mod._warmed_up = True
    gec_mod._device = torch.device("cpu")

    return fake_tokenizer, fake_model


@pytest.mark.slow
def test_correct_fixes_grammar():
    """Real inference — model must be pre-downloaded (~310MB)."""
    warmup()
    result = correct("the dog runned away from the park")
    assert "ran" in result.lower()


@pytest.mark.slow
def test_warmup_is_idempotent():
    warmup()
    model_first = gec_mod._model
    warmup()
    assert gec_mod._model is model_first


def test_hebrew_passthrough():
    result = correct("היי, זה טקסט עברי")
    assert result == "היי, זה טקסט עברי"


def test_hebrew_passthrough_no_model_needed():
    gec_mod._model = None
    gec_mod._warmed_up = False
    result = correct("שלום עולם")
    assert result == "שלום עולם"
    assert gec_mod._model is None


def test_not_warmed_raises_gec_not_available():
    gec_mod._model = None
    gec_mod._warmed_up = False
    with pytest.raises(GecNotAvailable):
        correct("some english text")


def test_placeholder_preservation():
    _install_mock_model(decoded="⟨⟨LP:abc123⟩⟩ is broken and fixed.")
    result = correct("⟨⟨LP:abc123⟩⟩ is broken")
    assert "⟨⟨LP:abc123⟩⟩" in result


def test_placeholder_lost_raises_gec_error():
    _install_mock_model(decoded="placeholder was stripped out.")
    with pytest.raises(GecError):
        correct("⟨⟨LP:abc123⟩⟩ input text")


def test_correct_returns_decoded_output():
    _install_mock_model(decoded="This is correct.")
    result = correct("this is correct")
    assert result == "This is correct."


def test_gec_not_available_when_not_warmed():
    gec_mod._model = None
    gec_mod._warmed_up = False
    with pytest.raises(GecNotAvailable):
        correct("some text here")
