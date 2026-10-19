"""Contracts 1.16-1.19 against PostgreSQL under RLS: BU Admin units and removal, technicians."""

import uuid
from typing import Any

from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, TARA, THEO, make_token
from tests.integration.test_s2_identity import P04, P05


def _key() -> dict[str, str]:
    return {"Idempotency-Key": str(uuid.uuid4())}


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _vacant_unit(api: Api) -> str:
    body = {
        "name": f"Plant {uuid.uuid4().hex[:6]}",
        "facility_name": "Akron",
        "bu_admin": {"invite_email": f"{uuid.uuid4().hex[:6]}@example.com"},
    }
    return str(api.post("/business-units", ERIN, json=body, headers=_key()).json()["bu_id"])


def _new_admin(api: Api) -> tuple[str, str]:
    """A fresh BU Admin of a fresh unit, through the real invite flow."""
    unit = _vacant_unit(api)
    email = f"{uuid.uuid4().hex[:6]}@example.com"
    api.post(
        "/invites",
        ERIN,
        json={"role": "bu_admin", "email": email, "bu_ids": [unit]},
        headers=_key(),
    )
    accepted = api.post(
        "/invites/accept", json={"token": api.sent[-1]["token"], "full_name": "Ada Admin"}
    )
    return str(accepted.json()["user_id"]), unit


def _new_technician(api: Api, phone: str) -> str:
    email = f"{uuid.uuid4().hex[:6]}@example.com"
    api.post(
        "/invites",
        BO,
        json={"role": "field_technician", "email": email, "bu_ids": [P04]},
        headers=_key(),
    )
    accepted = api.post(
        "/invites/accept",
        json={"token": api.sent[-1]["token"], "full_name": "Tom Tech", "phone_number": phone},
    )
    return str(accepted.json()["user_id"])


def _unit(api: Api, bu_id: str) -> dict[str, Any]:
    return next(
        u for u in api.get("/business-units?limit=100", ERIN).json()["items"] if u["bu_id"] == bu_id
    )


# --- 1.16 Edit units -----------------------------------------------------------------


def test_adding_a_unit_assigns_it_and_cancels_its_pending_invite(api: Api, owner_sql: Any) -> None:
    admin, first = _new_admin(api)
    second = _vacant_unit(api)  # comes with a pending BU Admin invite
    saved = api.put(f"/bu-admins/{admin}/business-units", ERIN, json={"bu_ids": [first, second]})
    assert saved.status_code == 200, saved.text
    assert {u["bu_id"] for u in saved.json()["units"]} == {first, second}
    assert _unit(api, second)["bu_admin"]["user_id"] == admin
    statuses = owner_sql("SELECT status FROM invite WHERE bu_id = %s", (second,))
    assert [s[0] for s in statuses] == ["cancelled"]


def test_dropping_a_unit_leaves_it_without_a_bu_admin(api: Api) -> None:
    admin, first = _new_admin(api)
    second = _vacant_unit(api)
    api.put(f"/bu-admins/{admin}/business-units", ERIN, json={"bu_ids": [first, second]})
    saved = api.put(f"/bu-admins/{admin}/business-units", ERIN, json={"bu_ids": [second]})
    assert [u["bu_id"] for u in saved.json()["units"]] == [second]
    assert saved.json()["status"] != "removed"  # still runs a unit (invited until first sign-in)
    assert _unit(api, first)["bu_admin"] is None
    assert admin not in api.keycloak.disabled  # still has a unit → login stays


def test_edit_units_rules(api: Api) -> None:
    admin, first = _new_admin(api)
    _problem(
        api.put(f"/bu-admins/{admin}/business-units", ERIN, json={"bu_ids": [first, P04]}),
        409,
        "unit-has-bu-admin",
    )  # Plant 04 is Bo's
    _problem(
        api.put(f"/bu-admins/{admin}/business-units", ERIN, json={"bu_ids": []}), 400, "validation"
    )
    _problem(
        api.put(f"/bu-admins/{uuid.uuid4()}/business-units", ERIN, json={"bu_ids": [first]}),
        404,
        "not-found",
    )
    _problem(
        api.put(f"/bu-admins/{TARA}/business-units", ERIN, json={"bu_ids": [first]}),
        404,
        "not-found",
    )  # not a BU Admin
    _problem(
        api.put(f"/bu-admins/{admin}/business-units", BO, json={"bu_ids": [first]}),
        403,
        "forbidden",
    )


# --- 1.17 Remove BU Admin -------------------------------------------------------------


def test_removing_from_every_unit_removes_the_account_and_can_invite_a_replacement(
    api: Api, owner_sql: Any
) -> None:
    admin, unit = _new_admin(api)
    replacement = f"{uuid.uuid4().hex[:6]}@example.com"
    removed = api.post(
        f"/bu-admins/{admin}/remove",
        ERIN,
        json={"bu_ids": [unit], "replacement_invite_email": replacement},
    )
    assert removed.status_code == 204, removed.text
    assert _unit(api, unit)["bu_admin"] is None
    assert api.sent[-1]["to"] == replacement
    pending = owner_sql("SELECT email FROM invite WHERE bu_id = %s AND status = 'pending'", (unit,))
    assert replacement in [p[0] for p in pending]
    _problem(api.get("/me", token=make_token(admin)), 403, "account-removed")
    sessions = owner_sql(
        "SELECT count(*) FROM user_session WHERE user_id = %s AND revoked_at IS NULL", (admin,)
    )
    assert sessions[0][0] == 0
    assert admin in api.keycloak.disabled  # Keycloak login disabled (docs/keycloak.md §6.11)


def test_remove_rules(api: Api) -> None:
    admin, unit = _new_admin(api)
    _problem(
        api.post(f"/bu-admins/{admin}/remove", ERIN, json={"bu_ids": [P04]}), 400, "validation"
    )
    _problem(api.post(f"/bu-admins/{admin}/remove", ERIN, json={"bu_ids": []}), 400, "validation")
    _problem(
        api.post(f"/bu-admins/{uuid.uuid4()}/remove", ERIN, json={"bu_ids": [unit]}),
        404,
        "not-found",
    )
    _problem(api.post(f"/bu-admins/{admin}/remove", BO, json={"bu_ids": [unit]}), 403, "forbidden")


# --- 1.18 / 1.19 Technicians -----------------------------------------------------------


def test_technicians_of_a_unit(api: Api, owner_sql: Any) -> None:
    listed = api.get(f"/business-units/{P04}/technicians", BO)
    assert listed.status_code == 200, listed.text
    people = {t["user_id"]: t for t in listed.json()["items"]}
    assert {TARA, THEO, DANA} <= set(people)  # Dana is a technician in Plant 04
    tara = people[TARA]
    this_month = owner_sql(
        "SELECT count(*) FROM scan WHERE technician_id = %s AND bu_id = %s"
        " AND created_at >= date_trunc('month', now())",
        (TARA, P04),
    )[0][0]
    assert (tara["status"], tara["scans_this_month"]) == ("active", this_month)
    assert tara["sign_in_locked_until"] is None  # OPEN O-13
    assert P04 in [u["bu_id"] for u in tara["units"]]
    _problem(
        api.get(f"/business-units/{P04}/technicians", ERIN), 403, "forbidden"
    )  # x-roles: bu_admin
    _problem(
        api.get(f"/business-units/{P04}/technicians", DANA), 403, "forbidden"
    )  # runs P05, not P04
    first = api.get(f"/business-units/{P04}/technicians?limit=1", BO).json()
    assert first["page"]["next_cursor"]


def test_removing_a_technician(api: Api) -> None:
    tech = _new_technician(api, f"+1555012{uuid.uuid4().int % 10000:04d}")
    assert api.get("/me", token=make_token(tech)).status_code == 200
    assert tech not in api.keycloak.disabled
    _problem(api.post(f"/business-units/{P05}/technicians/{tech}/remove", BO), 403, "forbidden")
    assert api.post(f"/business-units/{P04}/technicians/{tech}/remove", BO).status_code == 204
    assert tech not in [
        t["user_id"] for t in api.get(f"/business-units/{P04}/technicians", BO).json()["items"]
    ]
    _problem(api.get("/me", token=make_token(tech)), 403, "account-removed")  # no unit left
    assert tech in api.keycloak.disabled  # last unit → IdP login disabled too
    _problem(api.post(f"/business-units/{P04}/technicians/{tech}/remove", BO), 404, "not-found")
