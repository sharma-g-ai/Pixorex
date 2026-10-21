"""Flag rules for AI answers (FR-4.7) and data-type checks."""

from typing import Any

import pytest

from app.workers.extraction import checked_value, flags_for


def _field(**overrides: Any) -> dict[str, Any]:
    return {
        "data_type": "text",
        "options": None,
        "is_required": False,
        "is_critical": False,
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
        (_field(is_required=True), None, None, True, ["missing_required"]),
        (
            _field(is_required=True, is_critical=True),
            None,
            0.9,
            True,
            ["missing_required", "critical_not_found"],
        ),
        (_field(), None, None, True, []),  # optional and empty: nothing to check
        (_field(flag_below=0.5), "x", 0.6, True, []),  # the field's own threshold
    ],
)
def test_flags(
    field: dict[str, Any], value: str | None, confidence: float | None, fits: bool, flags: list[str]
) -> None:
    assert flags_for(field, value, confidence, fits) == flags


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
