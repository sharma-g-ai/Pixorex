"""DLP masking rules for CSV exports (services/dlp.py)."""

import pytest

from app.services.dlp import Masker, mask_name


def test_names_keep_only_their_first_letters() -> None:
    assert mask_name("Tara Tech") == "T*** T***"
    masker = Masker()
    assert masker.name("Bo Plant04") == "B*** P***"
    assert masker.name("System") == "System"  # not a person
    assert masker.name(None) is None
    assert masker.counts["names"] == 1


@pytest.mark.parametrize(
    ("value", "masked"),
    [
        ("Invited tara.tech@ppg.com as technician", "Invited t***@ppg.com as technician"),
        ("Call +15550100001 now", "Call +1******0001 now"),
        ("Call +1 555 010 0001", "Call +1 *** *** 0001"),
        ("(555) 010-0001", "(***) ***-0001"),
        ("555-010-0001", "***-***-0001"),
        ("Tara Tech approved it", "T*** T*** approved it"),
        ("TARA TECH", "T*** T***"),
    ],
)
def test_personal_data_in_text_is_masked(value: str, masked: str) -> None:
    assert Masker(known_names=["Tara Tech"]).text(value) == masked


@pytest.mark.parametrize(
    "value",
    ["SN 1234567890", "98274-A3", "CR 32-4-1 A-F-A-E-HQQE", "4I5 V", "480", "2026-10-19", "REC-12"],
)
def test_equipment_values_are_left_alone(value: str) -> None:
    masker = Masker(known_names=["Tara Tech"])
    assert masker.text(value) == value
    assert masker.summary() == "nothing masked"


def test_summary_counts_each_kind() -> None:
    masker = Masker(known_names=["Tara Tech"])
    masker.text("a@b.com and c@d.com, +15550100001, Tara Tech")
    assert masker.summary() == "masked 1 name, 2 emails, 1 phone"
