"""Slice S2 against PostgreSQL under RLS: /me, units, BU Admins, invites (contracts 1.1-1.15)."""

import time
import uuid
from typing import Any

from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, GUS, TARA, TENANT_A, make_token

P04 = str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/unit/p04"))
P05 = str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/unit/p05"))
P11 = str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/unit/p11"))
B_EA = str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/user/b-ea"))
B_TENANT = str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/tenant/b"))


def _key() -> dict[str, str]:
    return {"Idempotency-Key": str(uuid.uuid4())}


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


# --- Signing in (request context, A0) -------------------------------------------------


def test_me_returns_the_person_their_units_and_an_active_unit(api: Api) -> None:
    body = api.get("/me", BO).json()
    assert body["full_name"] == "Bo Plant04"
    assert [(u["bu_id"], u["role"]) for u in body["units"]] == [(P04, "bu_admin")]
    assert body["active_bu_id"] == P04


def test_first_sign_in_activates_an_invited_account(api: Api, owner_sql: Any) -> None:
    assert api.get("/me", ERIN).json()["status"] == "active"
    assert owner_sql("SELECT status FROM app_user WHERE id = %s", (ERIN,))[0][0] == "active"


def test_requests_without_device_or_valid_token_are_refused(api: Api) -> None:
    _problem(api.get("/me", BO, device=""), 400, "bad-request")
    _problem(api.get("/me"), 401, "unauthorized")
    _problem(api.get("/me", token=make_token(BO, aud="other-api")), 401, "unauthorized")
    _problem(api.get("/me", token=make_token(BO, azp="some-client")), 401, "unauthorized")
    _problem(api.get("/me", token=make_token(BO, exp=int(time.time()) - 120)), 401, "unauthorized")
    # A real user id under the wrong tenant finds nobody (RLS).
    _problem(api.get("/me", token=make_token(BO, tenant_id=B_TENANT)), 401, "unauthorized")


def test_removed_people_are_refused(api: Api) -> None:
    _problem(api.get("/me", GUS), 403, "account-removed")


def test_sign_out_stops_old_tokens_on_that_device_only(api: Api) -> None:
    old = make_token(TARA)
    assert api.get("/me", token=old, device="phone-a").status_code == 200
    assert api.get("/me", token=old, device="phone-b").status_code == 200
    assert api.post("/me/sign-out", token=old, device="phone-a").status_code == 204
    _problem(api.get("/me", token=old, device="phone-a"), 401, "unauthorized")
    assert api.get("/me", token=old, device="phone-b").status_code == 200
    fresh = make_token(TARA, iat=int(time.time()) + 2)  # signed in again afterwards
    assert api.get("/me", token=fresh, device="phone-a").status_code == 200


def test_switching_unit_needs_a_role_there(api: Api) -> None:
    _problem(api.put("/me/active-unit", BO, json={"bu_id": P05}), 403, "forbidden")
    switched = api.put("/me/active-unit", DANA, json={"bu_id": P04})
    assert switched.status_code == 200
    assert switched.json()["active_bu_id"] == P04


# --- Units and BU Admins ---------------------------------------------------------------


def test_units_follow_the_caller(api: Api) -> None:
    ea = {u["name"]: u for u in api.get("/business-units", ERIN).json()["items"]}
    assert {"Plant 04 — Coatings", "Plant 05 — Powder Coatings", "Plant 11 — Resins"} <= set(ea)
    assert ea["Plant 11 — Resins"]["bu_admin"] is None
    assert ea["Plant 04 — Coatings"]["bu_admin"]["full_name"] == "Bo Plant04"
    bo = {u["bu_id"] for u in api.get("/business-units", BO).json()["items"]}
    assert P04 in bo and not bo & {P05, P11}  # RLS: only units Bo runs
    _problem(api.get("/business-units", TARA), 403, "forbidden")
    other = api.get("/business-units", token=make_token(B_EA, tenant_id=B_TENANT)).json()
    assert [u["name"] for u in other["items"]] == ["Plant B1 — Sealants"]


def test_a_bu_admin_lists_only_the_units_they_run(api: Api) -> None:
    # Dana runs Plant 05 and is a technician in Plant 04.
    units = {u["bu_id"] for u in api.get("/business-units", DANA).json()["items"]}
    assert P05 in units and P04 not in units


def test_vacant_filter_and_paging(api: Api) -> None:
    vacant = api.get("/business-units?no_bu_admin=true", ERIN).json()["items"]
    assert P11 in [u["bu_id"] for u in vacant]
    assert all(u["bu_admin"] is None for u in vacant)
    first = api.get("/business-units?limit=1", ERIN).json()
    second = api.get(f"/business-units?limit=1&cursor={first['page']['next_cursor']}", ERIN).json()
    assert first["items"][0]["bu_id"] != second["items"][0]["bu_id"]
    _problem(api.get("/business-units?cursor=nonsense", ERIN), 400, "bad-request")


def test_bu_admins_list_is_for_the_ea(api: Api) -> None:
    admins = {a["full_name"]: a for a in api.get("/bu-admins", ERIN).json()["items"]}
    assert P04 in [u["bu_id"] for u in admins["Bo Plant04"]["units"]]
    assert [u["bu_id"] for u in admins["Dana Dual"]["units"]] == [P05]
    _problem(api.get("/bu-admins", BO), 403, "forbidden")


def test_creating_a_unit(api: Api, owner_sql: Any) -> None:
    name = f"Plant {uuid.uuid4().hex[:6]}"
    body = {
        "name": name,
        "facility_name": "Dayton",
        "bu_admin": {"invite_email": "new@example.com"},
    }
    created = api.post("/business-units", ERIN, json=body, headers=_key())
    assert created.status_code == 201, created.text
    unit = created.json()
    assert (unit["bu_admin"], unit["locations_status"]) == (None, "not_published")
    assert api.sent[-1]["to"] == "new@example.com"
    rows = owner_sql(
        "SELECT (SELECT count(*) FROM business_process WHERE bu_id = %s AND is_default),"
        " (SELECT count(*) FROM invite WHERE bu_id = %s AND role = 'bu_admin'),"
        " (SELECT count(*) FROM audit_log WHERE bu_id = %s)",
        (unit["bu_id"],) * 3,
    )
    assert rows[0] == (1, 1, 2)  # default process, the invite, two audit rows
    _problem(api.post("/business-units", ERIN, json=body, headers=_key()), 409, "duplicate-name")
    _problem(api.post("/business-units", BO, json=body, headers=_key()), 403, "forbidden")
    with_existing = {**body, "name": f"{name} B", "bu_admin": {"user_id": BO}}
    assert (
        api.post("/business-units", ERIN, json=with_existing, headers=_key()).json()["bu_admin"][
            "full_name"
        ]
        == "Bo Plant04"
    )
    not_admin = {**body, "name": f"{name} C", "bu_admin": {"user_id": TARA}}
    _problem(
        api.post("/business-units", ERIN, json=not_admin, headers=_key()), 409, "not-a-bu-admin"
    )


# --- Invites -----------------------------------------------------------------------------


def _new_vacant_unit(api: Api) -> str:
    body = {
        "name": f"Plant {uuid.uuid4().hex[:6]}",
        "facility_name": "Akron",
        "bu_admin": {"invite_email": f"{uuid.uuid4().hex[:6]}@example.com"},
    }
    return str(api.post("/business-units", ERIN, json=body, headers=_key()).json()["bu_id"])


def test_bu_admin_invite_from_link_to_account(api: Api, owner_sql: Any) -> None:
    unit = _new_vacant_unit(api)
    _problem(
        api.post(
            "/invites",
            ERIN,
            json={"role": "bu_admin", "email": "x@example.com", "bu_ids": [P04]},
            headers=_key(),
        ),
        409,
        "unit-has-bu-admin",
    )
    email = f"{uuid.uuid4().hex[:6]}@example.com"
    made = api.post(
        "/invites",
        ERIN,
        json={"role": "bu_admin", "email": email, "bu_ids": [unit]},
        headers=_key(),
    )
    assert made.status_code == 201, made.text
    token = api.sent[-1]["token"]

    preview = api.post("/invites/preview", json={"token": token})
    assert preview.status_code == 200, preview.text
    assert [u["bu_id"] for u in preview.json()["units"]] == [unit]

    accepted = api.post("/invites/accept", json={"token": token, "full_name": "Ana New"})
    assert accepted.status_code == 201, accepted.text
    assert accepted.json()["next_step"] == "verify_email"
    assert api.keycloak.users[-1].realm_role == "pixorex-web"
    user_id = accepted.json()["user_id"]
    # The trigger of migration 0002 made them the unit's BU Admin.
    assert (
        str(owner_sql("SELECT bu_admin_user_id FROM business_unit WHERE id = %s", (unit,))[0][0])
        == user_id
    )
    _problem(api.post("/invites/preview", json={"token": token}), 409, "invite-used")
    statuses = {i["email"]: i["status"] for i in api.get("/invites", ERIN).json()["items"]}
    assert statuses[email] == "accepted"


def test_technician_invite_rules(api: Api) -> None:
    _problem(
        api.post(
            "/invites",
            BO,
            json={"role": "field_technician", "email": "t@example.com", "bu_ids": [P05]},
            headers=_key(),
        ),
        403,
        "forbidden",
    )
    email = f"{uuid.uuid4().hex[:6]}@example.com"
    made = api.post(
        "/invites",
        BO,
        json={"role": "field_technician", "email": email, "bu_ids": [P04]},
        headers=_key(),
    )
    assert made.status_code == 201, made.text
    token = api.sent[-1]["token"]
    _problem(
        api.post("/invites/accept", json={"token": token, "full_name": "Tim"}), 400, "validation"
    )
    _problem(
        api.post(
            "/invites/accept",
            json={"token": token, "full_name": "Tim", "phone_number": "+15550100001"},
        ),  # Tara's number
        409,
        "phone-in-use",
    )
    ok = api.post(
        "/invites/accept",
        json={"token": token, "full_name": "Tim New", "phone_number": "+15550100099"},
    )
    assert ok.status_code == 201, ok.text
    assert ok.json()["next_step"] == "verify_phone"
    # Contract 1.9: the BU Admin sees technician invites of their units, the EA doesn't.
    assert email in [i["email"] for i in api.get("/invites", BO).json()["items"]]
    assert email not in [i["email"] for i in api.get("/invites", ERIN).json()["items"]]


def test_resend_replaces_the_link_and_cancel_ends_it(api: Api) -> None:
    unit = _new_vacant_unit(api)
    made = api.post(
        "/invites",
        ERIN,
        json={"role": "bu_admin", "email": "r@example.com", "bu_ids": [unit]},
        headers=_key(),
    )
    invite_id, old = made.json()["invite_ids"][0], api.sent[-1]["token"]
    assert api.post(f"/invites/{invite_id}/resend", ERIN).status_code == 200
    new = api.sent[-1]["token"]
    _problem(api.post("/invites/preview", json={"token": old}), 409, "invite-expired")
    assert api.post("/invites/preview", json={"token": new}).status_code == 200
    _problem(api.post(f"/invites/{invite_id}/resend", BO), 404, "not-found")  # not Bo's invite
    assert api.post(f"/invites/{invite_id}/cancel", ERIN).status_code == 204
    _problem(api.post("/invites/preview", json={"token": new}), 409, "invite-cancelled")
    _problem(api.post(f"/invites/{invite_id}/resend", ERIN), 409, "invalid-state")


def test_expired_and_unknown_links(api: Api, owner_sql: Any) -> None:
    unit = _new_vacant_unit(api)
    made = api.post(
        "/invites",
        ERIN,
        json={"role": "bu_admin", "email": "e@example.com", "bu_ids": [unit]},
        headers=_key(),
    )
    token = api.sent[-1]["token"]
    owner_sql(
        "UPDATE invite SET expires_at = now() - interval '1 minute' WHERE id = %s",
        (made.json()["invite_ids"][0],),
    )
    _problem(api.post("/invites/preview", json={"token": token}), 409, "invite-expired")
    expired = api.get("/invites?status=expired", ERIN).json()["items"]
    assert made.json()["invite_ids"][0] in [i["invite_id"] for i in expired]
    _problem(api.post("/invites/preview", json={"token": "x" * 43}), 409, "invite-expired")


def test_accepting_takes_the_same_persons_other_invites(api: Api, owner_sql: Any) -> None:
    first, second = _new_vacant_unit(api), _new_vacant_unit(api)
    email = f"{uuid.uuid4().hex[:6]}@example.com"
    for unit in (first, second):
        api.post(
            "/invites",
            ERIN,
            json={"role": "bu_admin", "email": email, "bu_ids": [unit]},
            headers=_key(),
        )
    newest = api.sent[-1]["token"]
    user_id = api.post("/invites/accept", json={"token": newest, "full_name": "Two Units"}).json()[
        "user_id"
    ]
    rows = owner_sql(
        "SELECT bu_id::text, is_primary FROM user_unit_role"
        " WHERE user_id = %s ORDER BY is_primary DESC",
        (user_id,),
    )
    assert {r[0] for r in rows} == {first, second}
    assert rows[0] == (first, True)  # D-09: the oldest invite's unit is primary


def test_tenants_never_see_each_others_invites(api: Api) -> None:
    other = api.get("/invites", token=make_token(B_EA, tenant_id=B_TENANT)).json()["items"]
    assert all(i["email"].endswith("@demo-b.local") for i in other)
    assert TENANT_A not in str(other)
