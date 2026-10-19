"""Contracts 3.1, 3.2, 3.15 against PostgreSQL: My Scans, self-review and fix, my batches."""

import uuid
from typing import Any

from tests.integration.capture_setup import (
    _attempt_ends,
    _body,
    _confirmed,
    _create,
    _key,
    _problem,
)
from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, TARA, TENANT_A


def _ready(api: Api, owner_sql: Any, unit: dict[str, str]) -> str:
    """A draft scan ready for self-review: serial read as SN-77 and flagged, voltage 480."""
    sid = _confirmed(api, unit)["scan_id"]
    attempt = owner_sql("SELECT id FROM extraction_attempt WHERE scan_id = %s", (sid,))[0][0]
    for field, value, confidence, flags in (
        (unit["fd"], "SN-77", 0.42, ["low_confidence"]),
        (unit["fd2"], "480", 0.97, []),
    ):
        owner_sql(
            "INSERT INTO ai_field_value (tenant_id, attempt_id, field_definition_id, value,"
            " confidence, flag_reasons) VALUES (%s, %s, %s, %s, %s, %s)",
            (TENANT_A, attempt, field, value, confidence, flags),
        )
    _attempt_ends(owner_sql, sid, "succeeded", "ready_to_review")
    return sid


def _submit(
    api: Api, sid: str, fields: list[dict[str, Any]], user: str = TARA, **extra: Any
) -> Any:
    return api.post(
        f"/scans/{sid}/revisions", user, headers=_key(), json={"fields": fields, **extra}
    )


def test_self_review_gate_and_submit_anyway(
    api: Api, owner_sql: Any, unit: dict[str, str], uploads: dict[str, bytes]
) -> None:
    early = _confirmed(api, unit)["scan_id"]
    _problem(_submit(api, early, []), 409, "invalid-state")  # still extracting

    sid = _ready(api, owner_sql, unit)
    _problem(_submit(api, sid, []), 409, "flags-not-reviewed")
    _problem(_submit(api, sid, [], user=DANA), 403, "forbidden")
    bad = [
        [{"field_key": "nope", "verification_state": "accepted"}],
        [{"field_key": "serial", "verification_state": "corrected", "value": " "}],
        [{"field_key": "serial", "verification_state": "unreadable"}],
        [{"field_key": "serial", "verification_state": "unreadable", "unreadable_reason": "other"}],
        [
            {
                "field_key": "serial",
                "verification_state": "accepted",
                "unreadable_reason": "label_worn",
            }
        ],
        [
            {"field_key": "serial", "verification_state": "accepted"},
            {"field_key": "serial", "verification_state": "accepted"},
        ],
    ]
    for fields in bad:
        _problem(_submit(api, sid, fields), 400, "validation")

    empty = [{"field_key": "serial", "verification_state": "left_empty"}]
    _problem(_submit(api, sid, empty), 409, "required-fields-empty")
    sent = _submit(api, sid, empty, submit_anyway=True)
    assert sent.status_code == 201, sent.text
    assert {k: v for k, v in sent.json().items() if k != "revision_id"} == {
        "revision_no": 1,
        "origin": "technician_review",
        "empty_required_fields": ["serial"],
        "review_status": "waiting_for_approval",
    }
    values = owner_sql("SELECT values_json FROM revision WHERE scan_id = %s", (sid,))[0][0]
    assert values == {"serial": None, "voltage": "480"}  # voltage kept as the AI read it
    verdicts = owner_sql(
        "SELECT field_key, verification_state, ai_field_value_id IS NOT NULL FROM revision_field"
        " rf JOIN revision r ON r.id = rf.revision_id WHERE r.scan_id = %s ORDER BY field_key",
        (sid,),
    )
    assert verdicts == [("serial", "left_empty", True), ("voltage", "accepted", True)]
    audited = owner_sql(
        "SELECT action, bu_id::text FROM audit_log WHERE object_id = %s AND category = 'review'",
        (sid,),
    )
    assert audited == [("scan.submitted", unit["bu"])]
    _problem(_submit(api, sid, empty, submit_anyway=True), 409, "invalid-state")  # sent already


def test_unreadable_is_not_empty_and_a_fix_goes_back_to_the_rejecter(
    api: Api, owner_sql: Any, unit: dict[str, str], uploads: dict[str, bytes]
) -> None:
    sid = _ready(api, owner_sql, unit)
    unreadable = [
        {
            "field_key": "serial",
            "verification_state": "unreadable",
            "unreadable_reason": "other",
            "note": "Painted over",
        }
    ]
    first = _submit(api, sid, unreadable)
    assert first.status_code == 201 and first.json()["empty_required_fields"] == [], first.text

    revision = first.json()["revision_id"]
    owner_sql(
        "INSERT INTO review_decision (tenant_id, revision_id, decided_by, decider_role, decision,"
        " reject_category) VALUES (%s, %s, %s, 'enterprise_admin', 'rejected',"
        " 'data_correction_needed')",
        (TENANT_A, revision, ERIN),
    )
    owner_sql("UPDATE scan SET review_status = 'rejected' WHERE id = %s", (sid,))
    fixed = _submit(
        api, sid, [{"field_key": "serial", "verification_state": "corrected", "value": "SN-1077"}]
    )
    assert fixed.status_code == 201, fixed.text
    assert (fixed.json()["revision_no"], fixed.json()["origin"]) == (2, "rejection_fix")
    back_to = owner_sql(
        "SELECT resubmit_to_user_id::text, values_json->>'serial' FROM revision"
        " WHERE scan_id = %s AND revision_no = 2",
        (sid,),
    )
    assert back_to == [(ERIN, "SN-1077")]


def test_my_scans_tabs_search_and_paging(
    api: Api, owner_sql: Any, unit: dict[str, str], uploads: dict[str, bytes]
) -> None:
    ready = _ready(api, owner_sql, unit)
    uploading = _create(api, unit, _body(unit)).json()["scan_id"]
    submitted = _ready(api, owner_sql, unit)
    sent = _submit(api, submitted, [{"field_key": "serial", "verification_state": "accepted"}])
    assert sent.status_code == 201, sent.text
    approved = _create(api, unit, _body(unit)).json()["scan_id"]
    owner_sql("UPDATE scan SET review_status = 'approved' WHERE id = %s", (approved,))
    _create(api, unit, _body(unit), user=DANA)  # someone else's

    def ids(**query: Any) -> list[str]:
        params = {"bu_id": unit["bu"], "limit": 100, **query}
        response = api.get("/me/scans", TARA, params=params)
        assert response.status_code == 200, response.text
        return [s["scan_id"] for s in response.json()["items"]]

    assert set(ids()) == {ready, uploading, submitted, approved}
    assert ids(tab="needs_action") == [ready]  # a submitted scan is not "needs action"
    assert set(ids(tab="in_progress")) == {uploading, submitted}
    assert ids(tab="approved") == [approved]
    assert ids(tab="all", q="SN-77") == [submitted]  # the submitted values
    assert len(ids(q="bin 14")) == 4  # the location
    assert ids(q="nothing-like-this") == []

    page = api.get("/me/scans", TARA, params={"bu_id": unit["bu"], "limit": 1}).json()
    item = page["items"][0]
    assert set(item) == {
        "scan_id",
        "record_no",
        "equipment_type_name",
        "location_path",
        "processing_status",
        "review_status",
        "attempts_used",
        "reject_category",
        "updated_at",
    }
    second = api.get(
        "/me/scans",
        TARA,
        params={"bu_id": unit["bu"], "limit": 1, "cursor": page["page"]["next_cursor"]},
    ).json()
    assert second["items"][0]["scan_id"] != item["scan_id"]
    _problem(api.get("/me/scans", BO), 403, "forbidden")  # not a technician


def test_my_review_batches_are_the_active_ones_given_to_me(
    api: Api, owner_sql: Any, unit: dict[str, str]
) -> None:
    def batch(status: str) -> str:
        return str(
            owner_sql(
                "INSERT INTO review_batch (tenant_id, bu_id, batch_no, assigned_to, created_by,"
                " status) VALUES (%s, %s, %s, %s, %s, %s) RETURNING id",
                (TENANT_A, unit["bu"], f"B-M{uuid.uuid4().hex[:6]}", DANA, ERIN, status),
            )[0][0]
        )

    active, _done = batch("active"), batch("completed")
    mine = api.get("/me/review-batches", DANA)
    assert mine.status_code == 200, mine.text
    assert active in [b["batch_id"] for b in mine.json()["items"]]
    assert _done not in [b["batch_id"] for b in mine.json()["items"]]
    assert active not in [
        b["batch_id"] for b in api.get("/me/review-batches", TARA).json()["items"]
    ]
    _problem(api.get("/me/review-batches", BO), 403, "forbidden")
