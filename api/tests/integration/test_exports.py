"""Contracts 4.1, 4.2 against PostgreSQL: CSV exports, scope (D-06), large exports."""

import csv
import io
import uuid
from typing import Any

from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, TARA, TENANT_A
from tests.integration.scans import waiting_scan
from tests.integration.test_s2_identity import P04, P05


def _key() -> dict[str, str]:
    return {"Idempotency-Key": str(uuid.uuid4())}


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _export(api: Api, user: str, **body: Any) -> Any:
    return api.post("/exports", user, headers=_key(), json=body)


def _rows(response: Any) -> list[dict[str, str]]:
    assert response.status_code == 200, response.text
    assert response.headers["content-type"].startswith("text/csv")
    return list(csv.DictReader(io.StringIO(response.text)))


def test_scans_csv_with_every_column_group(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA)
    rows = _rows(
        _export(
            api,
            BO,
            export_kind="scans",
            filters={"bu_id": P04},
            options={"columns": ["field_values", "ai_vs_technician", "review_decision"]},
        )
    )
    row = next(r for r in rows if r["Record no"] == scan["record_no"])
    assert (row["Unit"], row["Equipment type"], row["Captured by"], row["Review status"]) == (
        "Plant 04 — Coatings",
        "Test Pump",
        "Tara Tech",
        "waiting_for_approval",
    )
    assert (
        row["serial_number"],
        row["serial_number (AI)"],
        row["serial_number (AI confidence)"],
    ) == ("SN-1023", "SN-1O23", "0.41")
    assert row["Decision"] == ""
    plain = _rows(_export(api, BO, export_kind="scans"))
    assert "serial_number" not in plain[0] and "Record no" in plain[0]


def test_scope_follows_d06(api: Api, owner_sql: Any) -> None:
    _problem(_export(api, BO, export_kind="scans", filters={"bu_id": P05}), 403, "forbidden")
    _problem(_export(api, TARA, export_kind="scans"), 403, "forbidden")
    tara_scan = waiting_scan(owner_sql, TARA)  # Plant 04
    dana_rows = _rows(_export(api, DANA, export_kind="scans"))  # runs P05, technician in P04
    assert tara_scan["record_no"] not in [r["Record no"] for r in dana_rows]
    audit_rows = _rows(_export(api, BO, export_kind="audit_log"))
    assert {r["Unit"] for r in audit_rows} <= {"Plant 04 — Coatings"}
    assert list(audit_rows[0]) == ["When", "Who", "Unit", "Category", "Summary", "Action", "Object"]


def test_formulas_are_neutralised(api: Api, owner_sql: Any) -> None:
    owner_sql(
        "INSERT INTO audit_log (tenant_id, bu_id, actor_type, category, action, summary)"
        " VALUES (%s, %s, 'system', 'users', 'test', '=HYPERLINK(\"http://x\")')",
        (TENANT_A, P04),
    )
    rows = _rows(_export(api, ERIN, export_kind="audit_log", filters={"bu_id": P04}))
    assert '\'=HYPERLINK("http://x")' in [r["Summary"] for r in rows]


def test_large_exports_are_queued_and_only_the_requester_sees_the_job(
    api: Api, owner_sql: Any
) -> None:
    owner_sql(
        "INSERT INTO audit_log (tenant_id, bu_id, actor_type, category, action, summary)"
        " SELECT %s, %s, 'system', 'retention', 'bulk', 'row ' || g"
        " FROM generate_series(1, 1001) g",
        (TENANT_A, P04),
    )
    queued = _export(api, ERIN, export_kind="audit_log", filters={"category": "retention"})
    assert queued.status_code == 202, queued.text
    job = queued.json()
    assert (job["status"], job["row_count"] >= 1001, job["download_url"]) == ("queued", True, None)
    got = api.get(f"/exports/{job['export_id']}", ERIN)
    assert got.status_code == 200 and got.json()["status"] == "queued"
    _problem(api.get(f"/exports/{job['export_id']}", BO), 404, "not-found")
    audited = owner_sql("SELECT summary FROM audit_log WHERE object_id = %s", (job["export_id"],))
    assert "(queued)" in audited[0][0]
    _problem(
        _export(api, ERIN, export_kind="scans", filters={"from": "2026-10-10", "to": "2026-10-01"}),
        400,
        "validation",
    )


def test_a_bu_admins_export_shows_in_their_own_audit_log(api: Api) -> None:
    _rows(_export(api, BO, export_kind="scans"))
    mine = api.get("/audit-log?category=export&limit=5", BO).json()["items"]
    assert mine and mine[0]["summary"].startswith("Exported")
