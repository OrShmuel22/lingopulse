"""Unit tests for lingopulse.benchmark scoring functions."""
import json
import pathlib

import pytest

from lingopulse.benchmark import (
    _composite,
    _correctness_score,
    _latency_score,
    _length_stability_score,
    _quality_score_casual,
    _quality_score_professional,
)

# ---------------------------------------------------------------------------
# _latency_score — 5 piecewise regions
# ---------------------------------------------------------------------------


class TestLatencyScore:
    def test_at_zero_ms(self):
        assert _latency_score(0) == 100.0

    def test_at_500ms_boundary(self):
        assert _latency_score(500) == 100.0

    def test_middle_of_region_500_1500(self):
        # 500-1500: 100→70 over 1000ms. At 1000ms → 100 - (500/1000)*30 = 85
        score = _latency_score(1000)
        assert abs(score - 85.0) < 0.01

    def test_at_1500ms_boundary(self):
        # top of region 2: should be 70
        assert abs(_latency_score(1500) - 70.0) < 0.01

    def test_middle_of_region_1500_3000(self):
        # 1500-3000: 70→40 over 1500ms. At 2250ms → 70 - (750/1500)*30 = 55
        score = _latency_score(2250)
        assert abs(score - 55.0) < 0.01

    def test_at_3000ms_boundary(self):
        assert abs(_latency_score(3000) - 40.0) < 0.01

    def test_middle_of_region_3000_10000(self):
        # 3000-10000: 40→0 over 7000ms. At 6500ms → 40 - (3500/7000)*40 = 20
        score = _latency_score(6500)
        assert abs(score - 20.0) < 0.01

    def test_at_10000ms_boundary(self):
        assert abs(_latency_score(10000) - 0.0) < 0.01

    def test_above_10000ms(self):
        assert _latency_score(15000) == 0.0


# ---------------------------------------------------------------------------
# _correctness_score
# ---------------------------------------------------------------------------


class TestCorrectnessScore:
    def test_all_pass(self):
        checks = {"a": True, "b": True, "c": True}
        assert _correctness_score(checks) == 100.0

    def test_all_fail(self):
        checks = {"a": False, "b": False}
        assert _correctness_score(checks) == 0.0

    def test_half_pass(self):
        checks = {"a": True, "b": False}
        assert _correctness_score(checks) == 50.0

    def test_one_of_three_pass(self):
        checks = {"a": True, "b": False, "c": False}
        assert abs(_correctness_score(checks) - 100 / 3) < 0.01

    def test_empty_checks_returns_100(self):
        assert _correctness_score({}) == 100.0


# ---------------------------------------------------------------------------
# _quality_score_casual
# ---------------------------------------------------------------------------


class TestQualityScoreCasual:
    def test_fully_lowercase_sentences(self):
        # no sentence starts with a capital → ratio=0 → score=100
        score = _quality_score_casual("hey there. how's it going. sounds good")
        assert score == 100.0

    def test_all_capitalized_sentences(self):
        # ratio=1.0 → score should be 0
        score = _quality_score_casual("Hey. How. Good. Fine. Yes.")
        assert score == 0.0

    def test_quarter_capitalized(self):
        # 1 cap out of 4 = 0.25 ratio → exactly 100
        score = _quality_score_casual("Hello. hey. sure. ok")
        assert score == 100.0

    def test_empty_text(self):
        assert _quality_score_casual("") == 0.0

    def test_half_capitalized(self):
        # 2 cap out of 4 = 0.5 → 100*(1-0.5)/0.75 = 66.67
        score = _quality_score_casual("Hello. Fine. ok. sure")
        assert abs(score - 100.0 * 0.5 / 0.75) < 0.5


# ---------------------------------------------------------------------------
# _quality_score_professional
# ---------------------------------------------------------------------------


class TestQualityScoreProfessional:
    def test_all_proper_endings(self):
        score = _quality_score_professional("Hello. Please review. Thank you.")
        assert score == 100.0

    def test_no_proper_endings(self):
        score = _quality_score_professional("Hello Please review Thank you")
        assert score == 0.0

    def test_half_proper(self):
        score = _quality_score_professional("Hello. Please review")
        assert abs(score - 50.0) < 0.01

    def test_exclamation_accepted(self):
        score = _quality_score_professional("Done! Great work! Let us proceed.")
        assert score == 100.0

    def test_empty_text(self):
        assert _quality_score_professional("") == 0.0


# ---------------------------------------------------------------------------
# _length_stability_score
# ---------------------------------------------------------------------------


class TestLengthStabilityScore:
    def test_same_length(self):
        assert _length_stability_score(10, 10) == 100.0

    def test_within_band_low(self):
        # ratio=0.7 → 100
        assert _length_stability_score(10, 7) == 100.0

    def test_within_band_high(self):
        # ratio=1.4 → 100
        assert _length_stability_score(10, 14) == 100.0

    def test_below_band(self):
        # ratio=0.5 → midpoint between 0.3 and 0.7: (0.5-0.3)/(0.7-0.3)*100 = 50
        score = _length_stability_score(10, 5)
        assert abs(score - 50.0) < 0.01

    def test_way_below_band(self):
        # ratio=0.3 → 0
        assert _length_stability_score(10, 3) == 0.0

    def test_above_band(self):
        # ratio=2.2 → (3.0-2.2)/(3.0-1.4)*100 = 0.8/1.6*100 = 50
        score = _length_stability_score(10, 22)
        assert abs(score - 50.0) < 0.01

    def test_way_above_band(self):
        # ratio>=3.0 → 0
        assert _length_stability_score(10, 30) == 0.0

    def test_zero_original_zero_refined(self):
        assert _length_stability_score(0, 0) == 100.0

    def test_zero_original_nonzero_refined(self):
        assert _length_stability_score(0, 5) == 0.0


# ---------------------------------------------------------------------------
# _composite
# ---------------------------------------------------------------------------


class TestComposite:
    def test_all_100(self):
        assert _composite(100.0, 100.0, 100.0) == 100

    def test_all_zero(self):
        assert _composite(0.0, 0.0, 0.0) == 0

    def test_weights(self):
        # correctness=100, quality=0, latency=0 → 50
        assert _composite(100.0, 0.0, 0.0) == 50

    def test_weights_quality(self):
        # correctness=0, quality=100, latency=0 → 30
        assert _composite(0.0, 100.0, 0.0) == 30

    def test_weights_latency(self):
        # correctness=0, quality=0, latency=100 → 20
        assert _composite(0.0, 0.0, 100.0) == 20

    def test_rounding(self):
        # 50*0.5 + 50*0.3 + 50*0.2 = 25+15+10 = 50
        assert _composite(50.0, 50.0, 50.0) == 50

    def test_returns_int(self):
        result = _composite(80.0, 70.0, 60.0)
        assert isinstance(result, int)


# ---------------------------------------------------------------------------
# Scenarios JSON integrity
# ---------------------------------------------------------------------------


_SCENARIOS_PATH = pathlib.Path(__file__).parent.parent / "benchmarks" / "scenarios.json"


class TestScenariosJson:
    def test_file_exists(self):
        assert _SCENARIOS_PATH.exists(), "benchmarks/scenarios.json not found"

    def test_valid_json(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        assert isinstance(data, list)

    def test_at_least_25_scenarios(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        assert len(data) >= 25

    def test_all_have_id_and_endpoint(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        for sc in data:
            assert "id" in sc, f"Missing 'id' in scenario: {sc}"
            assert "endpoint" in sc, f"Missing 'endpoint' in scenario: {sc}"

    def test_unique_ids(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        ids = [sc["id"] for sc in data]
        assert len(ids) == len(set(ids)), "Duplicate scenario IDs found"

    def test_refine_scenarios_have_request(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        for sc in data:
            if sc["endpoint"] == "refine":
                assert "request" in sc, f"refine scenario {sc['id']} missing 'request'"
                assert "selection" in sc["request"], f"refine scenario {sc['id']} missing selection"
                assert "app" in sc["request"], f"refine scenario {sc['id']} missing app"

    def test_dictionary_scenarios_have_query(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        for sc in data:
            if sc["endpoint"] == "dictionary":
                assert "request" in sc, f"dictionary scenario {sc['id']} missing 'request'"
                assert "query" in sc["request"], f"dictionary scenario {sc['id']} missing query"

    def test_hebrew_scenarios_have_unicode(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        # Hebrew can appear via dictionary scenarios (expected_language=hebrew)
        # or via refine scenarios with must_contain_hebrew check.
        hebrew_dict = [sc for sc in data if sc.get("expected_language") == "hebrew"]
        hebrew_refine = [
            sc for sc in data
            if sc.get("endpoint") == "refine" and sc.get("checks", {}).get("must_contain_hebrew")
        ]
        total_hebrew = len(hebrew_dict) + len(hebrew_refine)
        assert total_hebrew >= 3, f"Expected at least 3 Hebrew scenarios (dict + refine), got {total_hebrew}"
        for sc in hebrew_dict:
            query = sc["request"]["query"]
            has_hebrew = any("֐" <= c <= "׿" for c in query)
            assert has_hebrew, f"Hebrew dict scenario {sc['id']} has no Hebrew chars: {query!r}"
        for sc in hebrew_refine:
            selection = sc["request"]["selection"]
            has_hebrew = any("֐" <= c <= "׿" for c in selection)
            assert has_hebrew, f"Hebrew refine scenario {sc['id']} has no Hebrew chars: {selection!r}"

    def test_undo_scenario_has_setup_refine(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        undo_scenarios = [sc for sc in data if sc["endpoint"] == "undo"]
        assert len(undo_scenarios) >= 1
        for sc in undo_scenarios:
            assert "setup_refine" in sc, f"undo scenario {sc['id']} missing setup_refine"

    def test_capture_style_scenario_exists(self):
        data = json.loads(_SCENARIOS_PATH.read_text(encoding="utf-8"))
        cap_scenarios = [sc for sc in data if sc["endpoint"] == "capture_style"]
        assert len(cap_scenarios) >= 1
