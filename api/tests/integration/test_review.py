"""Contracts 3.3-3.18 against PostgreSQL: queue, review, decisions, delegation, override,
escalations and the all-scans list."""

import uuid
from typing import Any
from urllib.parse import parse_qs, urlparse

from pydantic import SecretStr

from app.core.storage import StorageConfig
from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, TARA, THEO
from tests.integration.scans import escalate, waiting_scan
from tests.integration.test_s2_identity import P04


def _key() -> dict[str, str]:
    return {"Idempotency-Key": str(uuid.uuid4())}


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _decide(api: Api, user: str, scan_id: str, decision: str = "approved", **body: Any) -> Any:
    return api.post(
        f"/scans/{scan_id}/decisions", user, headers=_key(), json={"decision": decision, **body}
    )


def _notified(owner_sql: Any, user: str, kind: str, object_id: str) -> bool:
    return bool(
        owner_sql(
            "SELECT 1 FROM notification WHERE recipient_user_id = %s AND kind = %s"
            " AND object_id = %s",
            (user, kind, object_id),
        )
    )


# --- 3.3 queue / 3.4 review -------------------------------------------------------------


def test_queue_counts_and_items(api: Api, owner_sql: Any) -> None:
    fresh = waiting_scan(owner_sql, TARA)
    old = waiting_scan(owner_sql, TARA, hours_waiting=30)
    queue = api.get(f"/business-units/{P04}/review-queue?limit=100", BO)
    assert queue.status_code == 200, queue.text
    body = queue.json()
    items = {i["scan_id"]: i for i in body["items"]}
    assert {fresh["scan_id"], old["scan_id"]} <= set(items)
    item = items[fresh["scan_id"]]
    assert (item["flag_count"], item["corrected_count"], item["unreadable_count"]) == (2, 1, 1)
    assert (item["equipment_type_name"], item["captured_by_name"], item["batch_no"]) == (
        "Test Pump",
        "Tara Tech",
        None,
    )
    over = {
        i["scan_id"]
        for i in api.get(f"/business-units/{P04}/review-queue?filter=over_1d&limit=100", BO).json()[
            "items"
        ]
    }
    assert old["scan_id"] in over and fresh["scan_id"] not in over
    assert body["counts"]["waiting"] >= 2 and body["counts"]["over_1d"] >= 1
    assert api.get(f"/business-units/{P04}/review-queue", ERIN).status_code == 200
    _problem(api.get(f"/business-units/{P04}/review-queue", TARA), 403, "forbidden")
    _problem(
        api.get(f"/business-units/{P04}/review-queue", DANA), 403, "forbidden"
    )  # only a technician in P04


def test_scan_review_shows_ai_and_verdicts_never_to_the_own_technician(
    api: Api, owner_sql: Any
) -> None:
    scan = waiting_scan(owner_sql, TARA)
    review = api.get(f"/scans/{scan['scan_id']}/review", BO)
    assert review.status_code == 200, review.text
    body = review.json()
    assert [f["label"] for f in body["fields"]] == ["Serial number", "Voltage", "Phase"]
    serial = body["fields"][0]
    assert (serial["ai_value"], serial["technician_value"], serial["verification_state"]) == (
        "SN-1O23",
        "SN-1023",
        "corrected",
    )
    assert serial["confidence"] == 0.41 and serial["flag_reasons"] == ["low_confidence"]
    assert body["fields"][2]["unreadable_reason"] == "label_worn"
    assert body["current_revision"]["revision_no"] == 1 and body["decisions"] == []
    _problem(api.get(f"/scans/{scan['scan_id']}/review", TARA), 403, "own-scan")
    _problem(api.get(f"/scans/{scan['scan_id']}/review", THEO), 403, "forbidden")


# --- 3.5 decide ---------------------------------------------------------------------------


def test_first_decision_wins_and_resolves_escalations(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA)
    escalation = escalate(owner_sql, scan["scan_id"])
    decided = _decide(api, BO, scan["scan_id"])
    assert decided.status_code == 201, decided.text
    assert decided.json()["review_status"] == "approved"
    _problem(_decide(api, ERIN, scan["scan_id"]), 409, "already-decided")
    resolved = owner_sql(
        "SELECT resolved_by_decision_id FROM escalation WHERE id = %s", (escalation,)
    )
    assert str(resolved[0][0]) == decided.json()["decision_id"]
    assert _notified(owner_sql, TARA, "scan_approved", scan["scan_id"])
    decisions = api.get(f"/scans/{scan['scan_id']}/review", BO).json()["decisions"]
    assert (decisions[0]["decider_role"], decisions[0]["is_current"]) == ("bu_admin", True)


def test_decision_rules(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA)
    _problem(_decide(api, BO, scan["scan_id"], "rejected"), 400, "validation")  # no category
    _problem(_decide(api, BO, scan["scan_id"], reject_category="other"), 400, "validation")
    _problem(_decide(api, TARA, scan["scan_id"]), 403, "own-scan")
    empty = waiting_scan(owner_sql, TARA, empty_required=True)
    _problem(_decide(api, BO, empty["scan_id"]), 409, "invalid-state")  # FR-5.3: can't approve
    rejected = _decide(
        api, ERIN, empty["scan_id"], "rejected", reject_category="data_correction_needed"
    )
    assert rejected.status_code == 201
    assert _notified(owner_sql, TARA, "scan_rejected", empty["scan_id"])
    assert (
        api.get(f"/scans/{empty['scan_id']}/review", ERIN).json()["decisions"][0]["decider_role"]
        == "enterprise_admin"
    )


# --- 3.8 - 3.14 delegation ------------------------------------------------------------------


def test_delegation_from_batch_to_override(api: Api, owner_sql: Any) -> None:
    by_tara = waiting_scan(owner_sql, TARA)
    by_theo = waiting_scan(owner_sql, THEO)  # Theo's own: left out of his batch
    ids = [by_tara["scan_id"], by_theo["scan_id"]]
    delegates = api.get(f"/business-units/{P04}/delegates?scan_ids={','.join(ids)}", BO).json()[
        "items"
    ]
    theo = next(d for d in delegates if d["user_id"] == THEO)
    assert theo["own_scans_in_selection"] == 1

    created = api.post(
        f"/business-units/{P04}/review-batches",
        BO,
        headers=_key(),
        json={"assigned_to": THEO, "scan_ids": ids},
    )
    assert created.status_code == 201, created.text
    batch = created.json()
    assert batch["batch_no"].startswith("B-")
    assert batch["assigned_scan_ids"] == [by_tara["scan_id"]]
    assert batch["excluded"] == [{"scan_id": by_theo["scan_id"], "reason": "own_scan"}]
    assert _notified(owner_sql, THEO, "batch_delegated", batch["batch_id"])
    _problem(
        api.post(
            f"/business-units/{P04}/review-batches",
            BO,
            headers=_key(),
            json={"assigned_to": TARA, "scan_ids": [by_tara["scan_id"]]},
        ),
        409,
        "already-assigned",
    )
    queue = {
        i["scan_id"]: i
        for i in api.get(
            f"/business-units/{P04}/review-queue?filter=delegated&limit=100", BO
        ).json()["items"]
    }
    assert queue[by_tara["scan_id"]]["assigned_to_name"] == "Theo Invited"

    assert api.get(f"/review-batches/{batch['batch_id']}", THEO).status_code == 200
    assert api.get(f"/scans/{by_tara['scan_id']}/review", THEO).status_code == 200
    decided = _decide(api, THEO, by_tara["scan_id"])
    assert decided.status_code == 201, decided.text
    detail = api.get(f"/review-batches/{batch['batch_id']}", BO).json()
    assert (
        detail["batch"]["status"] == "completed" and detail["assignments"][0]["status"] == "decided"
    )

    tech_decisions = api.get(f"/business-units/{P04}/technician-decisions?limit=100", BO).json()[
        "items"
    ]
    mine = next(d for d in tech_decisions if d["decision_id"] == decided.json()["decision_id"])
    assert (mine["decided_by_name"], mine["overridden"]) == ("Theo Invited", False)

    overridden = api.post(
        f"/decisions/{decided.json()['decision_id']}/override",
        BO,
        headers=_key(),
        json={"decision": "rejected", "reject_category": "image_unclear"},
    )
    assert overridden.status_code == 201, overridden.text
    review = api.get(f"/scans/{by_tara['scan_id']}/review", BO).json()
    current = [d for d in review["decisions"] if d["is_current"]]
    assert (
        len(current) == 1 and current[0]["overrides_decision_id"] == decided.json()["decision_id"]
    )
    assert _notified(owner_sql, THEO, "decision_overridden", by_tara["scan_id"])
    _problem(
        api.post(
            f"/decisions/{decided.json()['decision_id']}/override",
            BO,
            headers=_key(),
            json={"decision": "approved"},
        ),
        409,
        "invalid-state",
    )  # no longer current


def test_admin_deciding_a_delegated_scan_takes_it_out_of_the_batch(
    api: Api, owner_sql: Any
) -> None:
    scan = waiting_scan(owner_sql, TARA)
    batch = api.post(
        f"/business-units/{P04}/review-batches",
        BO,
        headers=_key(),
        json={"assigned_to": THEO, "scan_ids": [scan["scan_id"]]},
    ).json()
    assert _decide(api, BO, scan["scan_id"]).status_code == 201
    assignment = api.get(f"/review-batches/{batch['batch_id']}", BO).json()["assignments"][0]
    assert (assignment["status"], assignment["removed_reason"]) == ("removed", "admin_decided")
    assert _notified(owner_sql, THEO, "scan_removed_from_batch", scan["scan_id"])


def test_reassign_take_back_and_remind(api: Api, owner_sql: Any) -> None:
    by_tara, by_dana = waiting_scan(owner_sql, TARA), waiting_scan(owner_sql, DANA)
    batch = api.post(
        f"/business-units/{P04}/review-batches",
        BO,
        headers=_key(),
        json={"assigned_to": THEO, "scan_ids": [by_tara["scan_id"], by_dana["scan_id"]]},
    ).json()
    reminded = api.post(f"/review-batches/{batch['batch_id']}/remind", BO)
    assert reminded.status_code == 200 and reminded.json()["reminded_at"]
    moved = api.post(
        f"/review-batches/{batch['batch_id']}/reassign", BO, json={"assigned_to": TARA}
    )
    assert moved.status_code == 200, moved.text
    assert moved.json()["excluded"] == [{"scan_id": by_tara["scan_id"], "reason": "own_scan"}]
    _problem(
        api.get(f"/scans/{by_dana['scan_id']}/review", THEO), 409, "invalid-state"
    )  # stale reviewer
    assert api.get(f"/scans/{by_dana['scan_id']}/review", TARA).status_code == 200
    assert (
        api.post(
            f"/review-batches/{batch['batch_id']}/take-back", BO, json={"message": "Busy week"}
        ).status_code
        == 204
    )
    detail = api.get(f"/review-batches/{batch['batch_id']}", BO).json()
    assert detail["batch"]["status"] == "taken_back"
    assert {a["removed_reason"] for a in detail["assignments"]} == {"taken_back", "reassigned"}
    _problem(api.post(f"/review-batches/{batch['batch_id']}/remind", BO), 409, "invalid-state")
    statuses = {
        b["batch_id"]: b["status"]
        for b in api.get(f"/business-units/{P04}/review-batches?limit=100", BO).json()["items"]
    }
    assert statuses[batch["batch_id"]] == "taken_back"


def test_an_ea_delegating_tells_the_bu_admin(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA)
    batch = api.post(
        f"/business-units/{P04}/review-batches",
        ERIN,
        headers=_key(),
        json={"assigned_to": THEO, "scan_ids": [scan["scan_id"]]},
    ).json()
    assert _notified(owner_sql, BO, "ea_delegated_in_unit", batch["batch_id"])
    _problem(
        api.post(
            f"/business-units/{P04}/review-batches",
            BO,
            headers=_key(),
            json={"assigned_to": BO, "scan_ids": [scan["scan_id"]]},
        ),
        400,
        "validation",
    )  # not a technician


# --- 3.16 - 3.18 ------------------------------------------------------------------------------


def test_escalations_and_reminding_the_bu_admin(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA, hours_waiting=26)
    escalate(owner_sql, scan["scan_id"])
    listed = api.get(f"/escalations?open=true&bu_id={P04}&limit=100", ERIN).json()["items"]
    mine = next(e for e in listed if e["scan_id"] == scan["scan_id"])
    assert (mine["reason"], mine["captured_by_name"], mine["equipment_type_name"]) == (
        "not_approved_24h",
        "Tara Tech",
        "Test Pump",
    )
    reminded = api.post(f"/business-units/{P04}/escalations/remind", ERIN)
    assert reminded.status_code == 200 and reminded.json()["reminded_count"] >= 1
    assert _notified(owner_sql, BO, "escalation_reminder", P04)
    _problem(api.get("/escalations", BO), 403, "forbidden")
    vacant = api.post(
        "/business-units",
        ERIN,
        headers=_key(),
        json={
            "name": f"Plant {uuid.uuid4().hex[:6]}",
            "facility_name": "X",
            "bu_admin": {"invite_email": "v@example.com"},
        },
    ).json()["bu_id"]
    _problem(api.post(f"/business-units/{vacant}/escalations/remind", ERIN), 409, "no-bu-admin")


def test_all_scans_for_the_ea(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA)
    escalate(owner_sql, scan["scan_id"], "no_bu_admin")
    found = api.get(f"/scans?q={scan['record_no']}", ERIN).json()["items"]
    assert [s["scan_id"] for s in found] == [scan["scan_id"]]
    row = found[0]
    assert (row["reviewed_by"], row["assignment"], row["escalation_reason"]) == (
        None,
        None,
        "no_bu_admin",
    )
    assert (
        row["bu_name"] == "Plant 04 — Coatings" and row["review_status"] == "waiting_for_approval"
    )
    _decide(api, BO, scan["scan_id"])
    row = api.get(f"/scans?q={scan['record_no']}", ERIN).json()["items"][0]
    assert row["reviewed_by"] == {"name": "Bo Plant04", "overrode_name": None}
    assert api.get("/scans?q=SN-1023&limit=100", ERIN).json()[
        "items"
    ]  # the serial, from the revision
    assert [
        s["record_no"]
        for s in api.get("/scans?q=Tara&review_status=approved&limit=100", ERIN).json()["items"]
    ]
    _problem(api.get("/scans", BO), 403, "forbidden")


# --- found in the line-by-line review ------------------------------------------------------


def test_delegates_accepts_repeated_scan_ids_as_the_web_sends_them(
    api: Api, owner_sql: Any
) -> None:
    by_theo_1, by_theo_2 = waiting_scan(owner_sql, THEO), waiting_scan(owner_sql, THEO)
    query = f"scan_ids={by_theo_1['scan_id']}&scan_ids={by_theo_2['scan_id']}"
    delegates = api.get(f"/business-units/{P04}/delegates?{query}", BO).json()["items"]
    assert next(d for d in delegates if d["user_id"] == THEO)["own_scans_in_selection"] == 2


def test_an_override_never_touches_a_newer_revision(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA)
    api.post(
        f"/business-units/{P04}/review-batches",
        BO,
        headers=_key(),
        json={"assigned_to": THEO, "scan_ids": [scan["scan_id"]]},
    )
    rejected = _decide(api, THEO, scan["scan_id"], "rejected", reject_category="image_unclear")
    # The technician fixes it: revision 2 waits for approval.
    owner_sql(
        "INSERT INTO revision (tenant_id, scan_id, revision_no, origin, values_json,"
        " submitted_by) SELECT tenant_id, id, 2, 'rejection_fix', '{}'::jsonb, technician_id"
        " FROM scan WHERE id = %s",
        (scan["scan_id"],),
    )
    owner_sql(
        "UPDATE scan SET review_status = 'waiting_for_approval' WHERE id = %s", (scan["scan_id"],)
    )
    _problem(
        api.post(
            f"/decisions/{rejected.json()['decision_id']}/override",
            BO,
            headers=_key(),
            json={"decision": "approved"},
        ),
        409,
        "invalid-state",
    )
    status = owner_sql("SELECT review_status FROM scan WHERE id = %s", (scan["scan_id"],))[0][0]
    assert status == "waiting_for_approval"


def test_no_reminder_when_nothing_is_escalated(api: Api, owner_sql: Any) -> None:
    p05 = str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/unit/p05"))  # Dana's, no scans
    before = owner_sql(
        "SELECT count(*) FROM notification WHERE recipient_user_id = %s"
        " AND kind = 'escalation_reminder'",
        (DANA,),
    )[0][0]
    reminded = api.post(f"/business-units/{p05}/escalations/remind", ERIN)
    assert reminded.status_code == 200 and reminded.json()["reminded_count"] == 0
    after = owner_sql(
        "SELECT count(*) FROM notification WHERE recipient_user_id = %s"
        " AND kind = 'escalation_reminder'",
        (DANA,),
    )[0][0]
    assert after == before


def test_unit_cards_count_waiting_escalated_and_delegated(api: Api, owner_sql: Any) -> None:
    def card() -> dict[str, Any]:
        units = api.get("/business-units?limit=100", ERIN).json()["items"]
        return next(u for u in units if u["bu_id"] == P04)

    before = card()
    one, two = waiting_scan(owner_sql, TARA), waiting_scan(owner_sql, TARA)
    escalate(owner_sql, one["scan_id"])
    api.post(
        f"/business-units/{P04}/review-batches",
        BO,
        headers=_key(),
        json={"assigned_to": THEO, "scan_ids": [two["scan_id"]]},
    )
    after = card()
    assert after["waiting_count"] == before["waiting_count"] + 2
    assert after["escalated_count"] == before["escalated_count"] + 1
    assert after["delegated_count"] == before["delegated_count"] + 1


def test_unit_cards_show_technicians_scans_this_month_and_vacancy(api: Api, owner_sql: Any) -> None:
    def card(bu: str) -> dict[str, Any]:
        units = api.get("/business-units?limit=100", ERIN).json()["items"]
        return next(u for u in units if u["bu_id"] == bu)

    before = card(P04)
    waiting_scan(owner_sql, TARA)
    after = card(P04)
    assert after["scans_this_month"] == before["scans_this_month"] + 1
    technicians = owner_sql(
        "SELECT count(*) FROM user_unit_role WHERE bu_id = %s AND role = 'field_technician'"
        " AND removed_at IS NULL",
        (P04,),
    )[0][0]
    assert after["technician_count"] == technicians >= 1
    assert (after["vacant_since"], after["previous_bu_admin"]) == (None, None)

    unit = api.post(
        "/business-units",
        ERIN,
        headers=_key(),
        json={
            "name": f"Plant {uuid.uuid4().hex[:6]}",
            "facility_name": "X",
            "bu_admin": {"invite_email": f"{uuid.uuid4().hex[:6]}@example.com"},
        },
    ).json()["bu_id"]
    fresh = card(unit)
    assert fresh["vacant_since"] and fresh["previous_bu_admin"] is None
    assert (fresh["technician_count"], fresh["scans_this_month"]) == (0, 0)
    # Its last BU Admin left on 4 Oct: the card says since when, and who.
    owner_sql(
        "INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role, removed_at)"
        " SELECT tenant_id, %s, %s, 'bu_admin', '2026-10-04T09:30:00Z' FROM business_unit"
        " WHERE id = %s",
        (DANA, unit, unit),
    )
    left = card(unit)
    assert left["vacant_since"].startswith("2026-10-04T09:30:00")
    assert left["previous_bu_admin"]["user_id"] == DANA


def test_review_photos_get_15_minute_links_only_for_reviewers(api: Api, owner_sql: Any) -> None:
    scan = waiting_scan(owner_sql, TARA)
    key = f"photos/{scan['scan_id']}/1.jpg"
    owner_sql(
        "INSERT INTO scan_photo (tenant_id, scan_id, photo_no, object_key, sha256)"
        " SELECT tenant_id, id, 1, %s, repeat('a', 64) FROM scan WHERE id = %s",
        (key, scan["scan_id"]),
    )
    path = f"/scans/{scan['scan_id']}/review"
    assert "url" not in api.get(path, BO).json()["photos"][0]  # no storage set up
    api.client.app.state.storage = StorageConfig(  # type: ignore[attr-defined]
        internal_url="http://minio:9000",
        public_url="http://localhost:9000",
        access_key="k",
        secret_key=SecretStr("s"),
        bucket="pixorex",
    )
    photo = api.get(path, BO).json()["photos"][0]
    link = urlparse(photo["url"])
    assert (photo["photo_no"], link.netloc, link.path) == (1, "localhost:9000", f"/pixorex/{key}")
    assert parse_qs(link.query)["X-Amz-Expires"] == ["900"]
    assert api.get(path, TARA).status_code == 403  # their own scan: no review, no link
