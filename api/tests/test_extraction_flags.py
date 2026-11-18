"""Flag rules for AI answers (FR-4.7) and data-type checks.

"Critical" and the AI's format verdict were removed by the 18 Nov 2026 change request: flags
come only from the field's own threshold, a missing confidence, an empty required field and a
value that does not fit its type."""

from typing import Any

import pytest

from app.workers.extraction import checked_value, flags_for


def _field(**overrides: Any) -> dict[str, Any]:
    return {
        "data_type": "text",
        "options": None,
        "is_required": False,
        "description": None,
        "flag_below": 0.85,
        **overrides,
    }


@pytest.mark.parametrize(
    ("field", "value", "confidence", "fits", "flags"),
    [
        (_field(), "SN-77", 0.95, True, []),
        (_field(), "SN-77", 0.42, True, ["low_confidence"]),
        (_field(), "SN-77", None, True, ["no_confidence"]),
        (_field(), "SN-77", 0.95, False, ["format_failed"]),
        (_field(), "SN-77", 0.42, False, ["low_confidence", "format_failed"]),
        (_field(is_required=True), None, None, True, ["missing_required"]),
        (_field(is_required=True), None, 0.9, True, ["missing_required"]),
        (_field(), None, None, True, []),  # optional and empty: nothing to check
    ],
)
def test_flags(
    field: dict[str, Any], value: str | None, confidence: float | None, fits: bool, flags: list[str]
) -> None:
    assert flags_for(field, value, confidence, fits) == flags


# Every threshold a BU Admin can set (0 to 100 %), against a confidence just below, equal
# to and just above it: below is flagged, equal or above is not.
THRESHOLDS = [0.0, 0.5, 0.85, 1.0]


@pytest.mark.parametrize("threshold", THRESHOLDS)
def test_the_fields_own_threshold_decides_low_confidence(threshold: float) -> None:
    field = _field(flag_below=threshold)
    below, above = threshold - 0.01, threshold + 0.01
    if threshold > 0:
        assert flags_for(field, "x", below, True) == ["low_confidence"]
    assert flags_for(field, "x", threshold, True) == []  # equal is not below
    if threshold < 1:
        assert flags_for(field, "x", above, True) == []


def test_a_threshold_of_100_percent_flags_everything_short_of_certain() -> None:
    assert flags_for(_field(flag_below=1.0), "x", 0.99, True) == ["low_confidence"]
    assert flags_for(_field(flag_below=1.0), "x", 1.0, True) == []


def test_a_threshold_of_0_never_flags_low_confidence() -> None:
    assert flags_for(_field(flag_below=0.0), "x", 0.0, True) == []


def test_critical_is_never_set_on_new_scans() -> None:
    # A field from before the change request may still carry is_critical in old data.
    old = _field(is_required=False, is_critical=True)
    assert "critical_not_found" not in flags_for(old, None, None, True)


@pytest.mark.parametrize(
    ("field", "value", "stored", "fits"),
    [
        (_field(data_type="number"), "480", "480", True),
        (_field(data_type="number"), "4I5", "4I5", False),
        (_field(data_type="number"), "480 V", "480 V", False),
        (_field(data_type="date"), "2026-10-19", "2026-10-19", True),
        (_field(data_type="date"), "19/10/26", "19/10/26", False),
        (_field(data_type="boolean"), "Yes", "true", True),
        (_field(data_type="boolean"), "maybe", "maybe", False),
        (_field(data_type="dropdown", options=["IP55", "IP66"]), "ip66", "IP66", True),
        (_field(data_type="dropdown", options=["IP55", "IP66"]), "IP44", "IP44", False),
        (_field(), "anything", "anything", True),
        (_field(data_type="number"), None, None, True),
    ],
)
def test_values_are_checked_against_their_type(
    field: dict[str, Any], value: str | None, stored: str | None, fits: bool
) -> None:
    assert checked_value(field, value) == (stored, fits)
