"""Repeat-safe creates: a stored Idempotency-Key returns the first answer for 24 hours."""

import uuid
from typing import Any

from app.workers import jobs
from tests.integration.conftest import Api
from tests.integration.helpers import BO, ERIN, TENANT_A
from tests.integration.test_s2_identity import P04


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _invite(api: Api, key: str, email: str, user: str = BO) -> Any:
    return api.post(
        "/invites",
        user,
        headers={"Idempotency-Key": key},
        json={"role": "field_technician", "email": email, "bu_ids": [P04]},
    )


def _unit(api: Api, key: str, name: str) -> Any:
    return api.post(
        "/business-units",
        ERIN,
        headers={"Idempotency-Key": key},
        json={
            "name": name,
            "facility_name": "Dayton",
            "bu_admin": {"invite_email": f"{uuid.uuid4().hex[:8]}@example.com"},
        },
    )


def test_a_repeated_create_returns_the_first_answer_once(api: Api, owner_sql: Any) -> None:
    key, email = str(uuid.uuid4()), f"{uuid.uuid4().hex[:8]}@example.com"
    first = _invite(api, key, email)
    assert first.status_code == 201, first.text
    emails = len(api.sent)
    again = _invite(api, key, email)
    assert (again.status_code, again.json()) == (201, first.json())
    assert len(api.sent) == emails  # no second email
    count = owner_sql("SELECT count(*) FROM invite WHERE lower(email) = %s", (email,))
    assert count[0][0] == 1


def test_one_key_for_another_request_is_refused(api: Api) -> None:
    key = str(uuid.uuid4())
    assert _invite(api, key, f"{uuid.uuid4().hex[:8]}@example.com").status_code == 201
    _problem(_invite(api, key, f"{uuid.uuid4().hex[:8]}@example.com"), 409, "idempotency-conflict")
    # The same key on another endpoint is another request too, for the same user.
    other = api.post(
        "/business-units",
        BO,
        headers={"Idempotency-Key": key},
        json={
            "name": "Plant X",
            "facility_name": "X",
            "bu_admin": {"invite_email": "x@example.com"},
        },
    )
    _problem(other, 409, "idempotency-conflict")


def test_keys_belong_to_one_user(api: Api) -> None:
    key = str(uuid.uuid4())
    assert _invite(api, key, f"{uuid.uuid4().hex[:8]}@example.com").status_code == 201
    unit = _unit(api, key, f"Plant {uuid.uuid4().hex[:6]}")  # Erin, same key: her own
    assert unit.status_code == 201, unit.text


def test_a_failed_request_is_not_remembered(api: Api) -> None:
    key, name = str(uuid.uuid4()), f"Plant {uuid.uuid4().hex[:6]}"
    assert _unit(api, str(uuid.uuid4()), name).status_code == 201
    _problem(_unit(api, key, name), 409, "duplicate-name")  # nothing stored
    _problem(_unit(api, key, name), 409, "duplicate-name")  # runs again, same answer
    fixed = _unit(api, key, f"{name} B")  # same key, corrected request
    assert fixed.status_code == 201, fixed.text


def test_a_csv_export_is_repeated_without_a_second_audit_row(api: Api, owner_sql: Any) -> None:
    key = str(uuid.uuid4())
    body = {"export_kind": "audit_log", "filters": {"category": "sign_in"}}
    first = api.post("/exports", ERIN, headers={"Idempotency-Key": key}, json=body)
    assert first.status_code == 200, first.text
    again = api.post("/exports", ERIN, headers={"Idempotency-Key": key}, json=body)
    assert again.status_code == 200 and again.content == first.content
    assert again.headers["content-type"].startswith("text/csv")
    assert again.headers["content-disposition"] == first.headers["content-disposition"]
    rows = owner_sql(
        "SELECT count(*) FROM idempotency_key WHERE key = %s AND operation = 'createExport'",
        (key,),
    )
    assert rows[0][0] == 1


async def test_keys_expire_after_24_hours(api: Api, owner_sql: Any, pool: Any) -> None:
    key = str(uuid.uuid4())
    assert _invite(api, key, f"{uuid.uuid4().hex[:8]}@example.com").status_code == 201
    owner_sql(
        "UPDATE idempotency_key SET created_at = now() - interval '25 hours',"
        " expires_at = now() - interval '1 hour' WHERE key = %s",
        (key,),
    )
    reused = _invite(api, key, f"{uuid.uuid4().hex[:8]}@example.com")  # expired: a new request
    assert reused.status_code == 201, reused.text
    owner_sql(
        "UPDATE idempotency_key SET created_at = now() - interval '25 hours',"
        " expires_at = now() - interval '1 hour' WHERE key = %s",
        (key,),
    )
    await jobs.run_all(pool)
    left = owner_sql(
        "SELECT count(*) FROM idempotency_key WHERE tenant_id = %s AND expires_at <= now()",
        (TENANT_A,),
    )
    assert left[0][0] == 0
