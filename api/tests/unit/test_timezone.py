"""Indian time, for every day, week and month (decision of 18 Nov 2026)."""

from datetime import UTC, datetime, timedelta

from app.core.timezone import IST, MONTH_DATE, MONTH_START, TZ, WEEK_START, as_ist, from_day, to_day


def test_ist_is_five_and_a_half_hours_ahead_of_utc() -> None:
    assert IST.utcoffset(None) == timedelta(hours=5, minutes=30)


def test_an_instant_is_read_on_the_indian_clock() -> None:
    # 18:29 UTC is 23:59 IST the same day; one minute later it is the next day in India.
    assert (
        as_ist(datetime(2026, 11, 17, 18, 29, tzinfo=UTC)).isoformat()
        == "2026-11-17T23:59:00+05:30"
    )
    assert (
        as_ist(datetime(2026, 11, 17, 18, 30, tzinfo=UTC)).isoformat()
        == "2026-11-18T00:00:00+05:30"
    )


def test_a_time_without_a_zone_is_taken_as_utc() -> None:
    assert as_ist(datetime(2026, 11, 18, 4, 0)).isoformat() == "2026-11-18T09:30:00+05:30"


def test_day_filters_name_the_zone_so_the_database_zone_does_not_matter() -> None:
    assert from_day("s.captured_at") == (
        f"s.captured_at >= (%s::date)::timestamp AT TIME ZONE '{TZ}'"
    )
    assert to_day("s.captured_at") == (
        f"s.captured_at < ((%s::date) + 1)::timestamp AT TIME ZONE '{TZ}'"
    )
    # One parameter each, so callers pass a single date.
    assert from_day("x").count("%s") == to_day("x").count("%s") == 1


def test_week_and_month_start_in_india() -> None:
    for sql in (WEEK_START, MONTH_START, MONTH_DATE):
        assert TZ in sql
    assert "'week'" in WEEK_START and "'month'" in MONTH_START
