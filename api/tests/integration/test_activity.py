"""Contracts 3.19-3.22 against PostgreSQL: audit log scope (D-06) and the notification bell."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, TARA, TENANT_A, make_token
from tests.integration.test_s2_identity import P04, P05


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _audit(owner_sql: Any, bu_id: str | None, summary: str, category: str = "users") -> None:
    owner_sql(
        "INSERT INTO audit_log (tenant_id, bu_id, actor_type, actor_user_id, category, action,"
        " summary, object_type) VALUES (%s, %s, 'user', %s, %s, 'test.action', %s, 'test')",
        (TENANT_A, bu_id, ERIN, category, summary),
    )


def test_ea_reads_every_unit_and_tenant_wide_rows(api: Api, owner_sql: Any) -> None:
    tag = uuid.uuid4().hex[:6]
    _audit(owner_sql, P04, f"p04 {tag}")
    _audit(owner_sql, P05, f"p05 {tag}")
    _audit(owner_sql, None, f"tenant {tag}", "sign_in")
    summaries = [e["summary"] for e in api.get("/audit-log?limit=100", ERIN).json()["items"]]
    assert {f"p04 {tag}", f"p05 {tag}", f"tenant {tag}"} <= set(summaries)
    entry = next(
        e
        for e in api.get("/audit-log?limit=100", ERIN).json()["items"]
        if e["summary"] == f"p04 {tag}"
    )
    assert (entry["actor_name"], entry["bu_name"], entry["details"]) == (
        "Erin Admin",
        "Plant 04 — Coatings",
        {},
    )


def test_a_bu_admin_reads_only_the_units_they_run(api: Api, owner_sql: Any) -> None:
    tag = uuid.uuid4().hex[:6]
    _audit(owner_sql, P04, f"p04 {tag}")
    _audit(owner_sql, P05, f"p05 {tag}")
    _audit(owner_sql, None, f"tenant {tag}", "sign_in")
    bo = {e["summary"] for e in api.get("/audit-log?limit=100", BO).json()["items"]}
    assert f"p04 {tag}" in bo and f"p05 {tag}" not in bo and f"tenant {tag}" not in bo
    # Dana runs Plant 05 and is only a technician in Plant 04 (RLS would show both).
    dana = {e["summary"] for e in api.get("/audit-log?limit=100", DANA).json()["items"]}
    assert f"p05 {tag}" in dana and f"p04 {tag}" not in dana
    _problem(api.get(f"/audit-log?bu_id={P05}", BO), 403, "forbidden")
    _problem(api.get("/audit-log", TARA), 403, "forbidden")


def test_filters_and_paging(api: Api, owner_sql: Any) -> None:
    tag = uuid.uuid4().hex[:6]
    _audit(owner_sql, P04, f"loc {tag}", "locations")
    by_category = api.get(f"/audit-log?bu_id={P04}&category=locations&limit=100", ERIN).json()[
        "items"
    ]
    assert all(e["category"] == "locations" for e in by_category)
    assert f"loc {tag}" in [e["summary"] for e in by_category]
    today = datetime.now(UTC).date()
    in_range = api.get(f"/audit-log?from={today}&to={today}&limit=100", ERIN).json()["items"]
    assert f"loc {tag}" in [e["summary"] for e in in_range]
    yesterday = today - timedelta(days=1)
    old = api.get(f"/audit-log?to={yesterday}&limit=100", ERIN).json()["items"]
    assert f"loc {tag}" not in [e["summary"] for e in old]
    _problem(api.get(f"/audit-log?from={today}&to={yesterday}", ERIN), 400, "validation")
    _problem(api.get("/audit-log?category=nonsense", ERIN), 400, "validation")
    first = api.get("/audit-log?limit=2", ERIN).json()
    second = api.get(f"/audit-log?limit=2&cursor={first['page']['next_cursor']}", ERIN).json()
    assert first["items"][-1]["occurred_at"] >= second["items"][0]["occurred_at"]


def _notify(owner_sql: Any, user: str, title: str) -> str:
    rows = owner_sql(
        "INSERT INTO notification (tenant_id, recipient_user_id, bu_id, kind, object_type,"
        " object_id, title, body)"
        " VALUES (%s, %s, %s, 'batch_reminder', 'review_batch', %s, %s, 'second line')"
        " RETURNING id",
        (TENANT_A, user, P04, str(uuid.uuid4()), title),
    )
    return str(rows[0][0])


def test_the_bell_shows_only_your_own_notifications(api: Api, owner_sql: Any) -> None:
    user = TARA
    api.post("/me/notifications/read-all", user)
    first = _notify(owner_sql, user, "First")
    second = _notify(owner_sql, user, "Second")
    other = _notify(owner_sql, BO, "For Bo")
    page = api.get("/me/notifications", user).json()
    titles = [n["title"] for n in page["items"]]
    assert titles[:2] == ["Second", "First"] and "For Bo" not in titles  # newest first
    assert page["unread_count"] == 2
    assert page["items"][0]["body"] == "second line" and page["items"][0]["emailed_at"] is None

    assert api.post(f"/me/notifications/{first}/read", user).status_code == 204
    assert api.get("/me/notifications", user).json()["unread_count"] == 1
    unread = api.get("/me/notifications?unread_only=true", user).json()["items"]
    assert [n["notification_id"] for n in unread] == [second]
    _problem(api.post(f"/me/notifications/{other}/read", user), 404, "not-found")  # Bo's
    assert api.post("/me/notifications/read-all", user).status_code == 204
    assert api.get("/me/notifications", user).json()["unread_count"] == 0
    assert api.get("/me/notifications", BO).json()["unread_count"] >= 1  # untouched


def test_other_tenants_see_nothing(api: Api, owner_sql: Any) -> None:
    tag = uuid.uuid4().hex[:6]
    _audit(owner_sql, P04, f"a {tag}")
    b_ea = make_token(
        str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/user/b-ea")),
        tenant_id=str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/tenant/b")),
    )
    summaries = [e["summary"] for e in api.get("/audit-log?limit=100", token=b_ea).json()["items"]]
    assert f"a {tag}" not in summaries
