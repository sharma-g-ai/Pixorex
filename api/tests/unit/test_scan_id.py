"""Scan IDs: a 9-digit counter per tenant and a Luhn check digit (lead, 5 Nov 2026)."""

from app.repositories.scans import FIRST_RECORD, luhn_digit, record_no_for


def _valid(scan_id: str) -> bool:
    return luhn_digit(scan_id[:9]) == int(scan_id[9])


def test_scan_ids_have_ten_digits_and_a_luhn_check_digit() -> None:
    assert record_no_for(FIRST_RECORD) == "1000000016"
    assert record_no_for(100_000_004) == "1000000040"
    assert luhn_digit("7992739871") == 3  # the textbook example


def test_the_check_digit_catches_one_wrong_digit_and_a_swap() -> None:
    good = record_no_for(100_000_123)
    assert _valid(good)
    assert not _valid("100000133" + good[9])  # one digit wrong
    assert not _valid("100000132" + good[9])  # two neighbours swapped
