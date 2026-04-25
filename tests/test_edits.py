import lingopulse.edits as edits_mod


def test_simple_replace_classified_as_preposition():
    edits = edits_mod.compute_edits("responsible on the team", "responsible for the team")
    assert len(edits) == 1
    e = edits[0]
    assert e["type"] == "replace"
    assert e["from_text"] == "on"
    assert e["to_text"] == "for"
    assert e["category"] == "preposition"


def test_plural_uncountable_classified():
    edits = edits_mod.compute_edits("many informations here", "many information here")
    assert edits[0]["category"] == "plural"
    assert "uncountable" in edits[0]["reason"].lower()


def test_calque_until_by_classified():
    edits = edits_mod.compute_edits("finish until tomorrow morning", "finish by tomorrow morning")
    assert edits[0]["from_text"] == "until"
    assert edits[0]["to_text"] == "by"


def test_multiple_edits_in_one_input():
    edits = edits_mod.compute_edits(
        "i have informations and feedbacks here",
        "i have information and feedback here",
    )
    assert len(edits) == 2
    assert all(e["category"] == "plural" for e in edits)


def test_insert_only():
    edits = edits_mod.compute_edits("responsible the team", "responsible for the team")
    assert edits[0]["type"] == "insert"
    assert edits[0]["to_text"] == "for"
    assert edits[0]["from_text"] == ""


def test_delete_only():
    edits = edits_mod.compute_edits("this is just a test", "this is a test")
    assert edits[0]["type"] == "delete"
    assert edits[0]["from_text"] == "just"


def test_apply_subset_of_edits_cherry_picks():
    orig = "many informations and feedbacks"
    refined = "many information and feedback"
    result = edits_mod.apply_edits(orig, refined, [0])
    assert "information" in result
    assert "feedbacks" in result


def test_apply_all_edits_equals_refined():
    orig = "many informations and feedbacks"
    refined = "many information and feedback"
    edits = edits_mod.compute_edits(orig, refined)
    assert edits_mod.apply_edits(orig, refined, list(range(len(edits)))) == refined


def test_apply_empty_acceptance_equals_original():
    assert edits_mod.apply_edits("hello world", "Hello world!", []) == "hello world"


def test_span_indices_correct():
    edits = edits_mod.compute_edits("one two three four", "one TWO three four")
    assert edits[0]["from_span"] == [1, 2]
    assert edits[0]["to_span"] == [1, 2]
