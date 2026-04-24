import re

_tokenizer = None
_model = None
_device = None
_warmed_up = False

_MODEL_ID = "pszemraj/grammar-synthesis-small"
_PLACEHOLDER_RE = re.compile(r"⟨⟨LP:[0-9a-f]+⟩⟩")
_HEBREW_RE = re.compile(r"[֐-׿]")


class GecError(Exception):
    pass


class GecNotAvailable(GecError):
    pass


def _load():
    global _tokenizer, _model, _device, _warmed_up
    if _model is not None:
        return

    try:
        import torch
        from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
    except ImportError as exc:
        raise GecNotAvailable("torch or transformers not installed") from exc

    try:
        _tokenizer = AutoTokenizer.from_pretrained(_MODEL_ID)
        _model = AutoModelForSeq2SeqLM.from_pretrained(_MODEL_ID, dtype=torch.float32)
    except Exception as exc:
        raise GecNotAvailable(f"Failed to load GEC model: {exc}") from exc

    if torch.backends.mps.is_available():
        _device = torch.device("mps")
    else:
        _device = torch.device("cpu")

    _model.to(_device)
    _model.eval()
    _warmed_up = True


def warmup() -> None:
    """Load model into memory. Blocking. Safe to call multiple times."""
    _load()


def correct(text: str, max_length: int = 512) -> str:
    """Return grammar-corrected text. Preserves ⟨⟨LP:xxx⟩⟩ placeholders verbatim."""
    if _HEBREW_RE.search(text):
        return text

    if not _warmed_up and _model is None:
        raise GecNotAvailable("GEC model not loaded — call warmup() first")

    _load()

    placeholders = _PLACEHOLDER_RE.findall(text)

    inputs = _tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        max_length=512,
    ).to(_device)

    with _no_grad():
        output_ids = _model.generate(**inputs, max_length=max_length, num_beams=1)

    result = _tokenizer.decode(output_ids[0], skip_special_tokens=True)

    for ph in placeholders:
        if ph not in result:
            raise GecError(f"Placeholder {ph!r} lost during GEC inference")

    return result


def is_loaded() -> bool:
    """Return True if the GEC model has been successfully warmed up."""
    return _model is not None and _tokenizer is not None


def _no_grad():
    import torch
    return torch.no_grad()
