"""One time zone for every day, week and month the product counts: Indian time (IST).

Decision of 18 Nov 2026. Times are stored in UTC (timestamptz) and sent with their offset; this
module is only how a "day" is read. A From/To day filter, "this week", "this month" and the
times written to a CSV all use it, so a screen, an export and a count never disagree.

India has no daylight saving, so IST is a fixed UTC+5:30. The SQL side names the zone so the
database does the work (and stays right whatever its own time zone is set to).
"""

from datetime import UTC, datetime, timedelta, timezone

TZ = "Asia/Kolkata"
IST = timezone(timedelta(hours=5, minutes=30), "IST")


def from_day(column: str) -> str:
    """SQL: [column] is on or after the start of the given day (one %s, a date), IST."""
    return f"{column} >= (%s::date)::timestamp AT TIME ZONE '{TZ}'"


def to_day(column: str) -> str:
    """SQL: [column] is before the end of the given day (one %s, a date), IST: the whole day
    is included."""
    return f"{column} < ((%s::date) + 1)::timestamp AT TIME ZONE '{TZ}'"


# SQL: the first instant of this week (Monday 00:00) and this month (the 1st, 00:00), IST.
WEEK_START = f"date_trunc('week', now() AT TIME ZONE '{TZ}') AT TIME ZONE '{TZ}'"
MONTH_START = f"date_trunc('month', now() AT TIME ZONE '{TZ}') AT TIME ZONE '{TZ}'"
# SQL: the first day of this month on the Indian calendar, as a date (the quota period key).
MONTH_DATE = f"date_trunc('month', now() AT TIME ZONE '{TZ}')::date"


def as_ist(value: datetime) -> datetime:
    """An instant on the Indian clock. A time without a zone is taken as UTC (that is how
    the database hands times over)."""
    return (value if value.tzinfo else value.replace(tzinfo=UTC)).astimezone(IST)
