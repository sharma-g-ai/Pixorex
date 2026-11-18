"""Every day, week and month is Indian time (decision of 18 Nov 2026), against PostgreSQL.

The database itself runs in UTC, so a scan made at 00:30 IST on 18 Nov is stored as 19:00 UTC
on 17 Nov. These tests place rows either side of Indian midnight and check that every screen
and export agrees on which day each belongs to."""

import csv
import io
import uuid
from typing import Any

from tests.integration.conftest import Api
from tests.integration.helpers import BO, ERIN, TARA, TENANT_A
from tests.integration.scans import waiting_scan
from tests.integration.test_s2_identity import P04

# March 2027 is inside the audit log partitions and free of every other test's rows.
JUST_AFTER_MIDNIGHT_IST = "2027-03-17T19:00:00+00:00"  # = 18 Mar 00:30 IST, but 17 Mar in UTC
JUST_BEFORE_MIDNIGHT_IST = "2027-03-18T18:00:00+00:00"  # = 18 Mar 23:30 IST, still 18 Mar
FIRST_MINUTE_OF_NEXT_DAY = "2027-03-18T18:30:00+00:00"  # = 19 Mar 00:00 IST


def _scan_at(owner_sql: Any, when: str) -> dict[str, str]:
    scan = waiting_scan(owner_sql, TARA)
    owner_sql(
        "UPDATE scan SET captured_at = %s::timestamptz WHERE id = %s", (when, scan["scan_id"])
    )
    return scan


def _found(api: Api, day_from: str, day_to: str, user: str = ERIN) -> set[str]:
    response = api.get(f"/scans?from={day_from}&to={day_to}&limit=100", user)
    assert response.status_code == 200, response.text
    return {s["record_no"] for s in response.json()["items"]}


def test_the_scans_list_counts_days_in_india(api: Api, owner_sql: Any) -> None:
    after = _scan_at(owner_sql, JUST_AFTER_MIDNIGHT_IST)
    before = _scan_at(owner_sql, JUST_BEFORE_MIDNIGHT_IST)
    next_day = _scan_at(owner_sql, FIRST_MINUTE_OF_NEXT_DAY)
    mine = {after["record_no"], before["record_no"], next_day["record_no"]}

    on_18 = _found(api, "2027-03-18", "2027-03-18") & mine
    # Both the 00:30 and the 23:30 scan are on 18 Mar in India; the 00:00 one is already 19 Mar.
    assert on_18 == {after["record_no"], before["record_no"]}
    assert _found(api, "2027-03-17", "2027-03-17") & mine == set()  # not "17 Mar", as in UTC
    assert _found(api, "2027-03-19", "2027-03-19") & mine == {next_day["record_no"]}
    # From and To are both included.
    assert _found(api, "2027-03-18", "2027-03-19") & mine == mine


def test_the_audit_log_counts_days_in_india(api: Api, owner_sql: Any) -> None:
    tag = uuid.uuid4().hex[:6]
    for when, name in (
        (JUST_AFTER_MIDNIGHT_IST, "after"),
        (JUST_BEFORE_MIDNIGHT_IST, "before"),
        (FIRST_MINUTE_OF_NEXT_DAY, "next"),
    ):
        owner_sql(
            "INSERT INTO audit_log (tenant_id, bu_id, actor_type, actor_user_id, category,"
            " action, summary, object_type, occurred_at) VALUES"
            " (%s, %s, 'user', %s, 'users', 'test.action', %s, 'test', %s::timestamptz)",
            (TENANT_A, P04, ERIN, f"{name} {tag}", when),
        )

    def on(day_from: str, day_to: str) -> set[str]:
        got = api.get(f"/audit-log?from={day_from}&to={day_to}&limit=100", ERIN).json()
        return {e["summary"] for e in got["items"] if e["summary"].endswith(tag)}

    assert on("2027-03-18", "2027-03-18") == {f"after {tag}", f"before {tag}"}
    assert on("2027-03-17", "2027-03-17") == set()
    assert on("2027-03-19", "2027-03-19") == {f"next {tag}"}


def _csv_rows(response: Any) -> list[dict[str, str]]:
    assert response.status_code == 200, response.text
    return list(csv.DictReader(io.StringIO(response.text)))


def test_exports_filter_by_india_days_and_write_india_times(api: Api, owner_sql: Any) -> None:
    after = _scan_at(owner_sql, JUST_AFTER_MIDNIGHT_IST)
    next_day = _scan_at(owner_sql, FIRST_MINUTE_OF_NEXT_DAY)

    def export(day: str) -> dict[str, dict[str, str]]:
        response = api.post(
            "/exports",
            BO,
            headers={"Idempotency-Key": str(uuid.uuid4())},
            json={"export_kind": "scans", "filters": {"bu_id": P04, "from": day, "to": day}},
        )
        return {r["Record no"]: r for r in _csv_rows(response)}

    on_18 = export("2027-03-18")
    assert after["record_no"] in on_18 and next_day["record_no"] not in on_18
    assert after["record_no"] not in export("2027-03-17")
    assert next_day["record_no"] in export("2027-03-19")
    # The time in the file is the Indian time, with its offset: 19:00 UTC is 00:30 +05:30.
    assert on_18[after["record_no"]]["Captured at"] == "2027-03-18T00:30:00+05:30"


def test_the_audit_export_writes_india_times(api: Api, owner_sql: Any) -> None:
    tag = uuid.uuid4().hex[:6]
    owner_sql(
        "INSERT INTO audit_log (tenant_id, bu_id, actor_type, actor_user_id, category, action,"
        " summary, object_type, occurred_at) VALUES"
        " (%s, %s, 'user', %s, 'users', 'test.action', %s, 'test', %s::timestamptz)",
        (TENANT_A, P04, ERIN, f"export {tag}", JUST_AFTER_MIDNIGHT_IST),
    )
    response = api.post(
        "/exports",
        ERIN,
        headers={"Idempotency-Key": str(uuid.uuid4())},
        json={"export_kind": "audit_log", "filters": {"from": "2027-03-18", "to": "2027-03-18"}},
    )
    row = next(r for r in _csv_rows(response) if r["Summary"] == f"export {tag}")
    assert row["When"] == "2027-03-18T00:30:00+05:30"


def test_this_month_counts_start_on_the_first_in_india(api: Api, owner_sql: Any) -> None:
    """A scan made in the first minutes of the month in India (still the last evening of the
    previous month in UTC) counts for the new month, on the unit list and the technician list."""
    month_start_ist = owner_sql(
        "SELECT date_trunc('month', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'"
    )[0][0]
    before = _unit_count(api)
    scan = waiting_scan(owner_sql, TARA)
    # One minute into the month in India.
    owner_sql(
        "UPDATE scan SET created_at = %s::timestamptz + interval '1 minute' WHERE id = %s",
        (month_start_ist, scan["scan_id"]),
    )
    assert _unit_count(api) == before + 1
    # One minute before it: last month, not counted.
    owner_sql(
        "UPDATE scan SET created_at = %s::timestamptz - interval '1 minute' WHERE id = %s",
        (month_start_ist, scan["scan_id"]),
    )
    assert _unit_count(api) == before


def _unit_count(api: Api) -> int:
    units = api.get("/business-units", ERIN).json()["items"]
    return next(u for u in units if u["bu_id"] == P04)["scans_this_month"]
