"""Contracts 2.21-2.27 against PostgreSQL: create a scan, upload photos, confirm, read, retry,
re-extract, discard."""

import hashlib
import uuid
from typing import Any

from app.repositories.scans import PATH_SEPARATOR
from app.workers import outbox
from app.workers.settings import WorkerSettings
from tests.integration.capture_setup import (
    JPEG,
    _attempt_ends,
    _body,
    _confirmed,
    _create,
    _digest,
    _id,
    _key,
    _problem,
    _put,
    _quota,
)
from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, TARA, TENANT_A


def test_create_scan_is_repeat_safe_and_counts_once(
    api: Api, owner_sql: Any, unit: dict[str, str]
) -> None:
    body = _body(unit)
    first = _create(api, unit, body)
    assert first.status_code == 201, first.text
    scan = first.json()
    assert scan["record_no"].startswith("REC-")
    assert scan["location_path"] == PATH_SEPARATOR.join(["Akron", "Building A", "Bin 14"])
    assert (scan["processing_status"], scan["review_status"]) == ("uploading", "draft")
    assert (scan["photos"], scan["attempts_used"], scan["fields"]) == ([], 0, [])
    assert _quota(owner_sql, unit["bu"]) == 1

    again = _create(api, unit, body)
    assert again.status_code == 200 and again.json()["scan_id"] == scan["scan_id"]
    assert _quota(owner_sql, unit["bu"]) == 1  # a retry never counts twice
    _problem(
        _create(api, unit, {**body, "captured_at": "2026-10-19T10:00:00Z"}),
        409,
        "idempotency-conflict",
    )
    _problem(_create(api, unit, body, user=DANA), 409, "idempotency-conflict")  # someone else's

    second = _create(api, unit, _body(unit)).json()
    assert int(second["record_no"][4:]) > int(scan["record_no"][4:])
    assert _quota(owner_sql, unit["bu"]) == 2


def test_create_scan_rules(api: Api, owner_sql: Any, unit: dict[str, str]) -> None:
    body = _body(unit)
    mismatch = api.post(
        f"/business-units/{unit['bu']}/scans", TARA, headers={"Idempotency-Key": _id()}, json=body
    )
    _problem(mismatch, 400, "validation")
    _problem(_create(api, unit, _body(unit), user=BO), 403, "forbidden")  # not a technician here
    _problem(_create(api, unit, _body(unit, photo_count=5)), 400, "validation")
    _problem(_create(api, unit, _body(unit, captured_at="2026-10-19T09:30:00")), 400, "validation")
    owner_sql("UPDATE equipment_type SET status = 'not_published' WHERE id = %s", (unit["type"],))
    _problem(_create(api, unit, _body(unit)), 409, "type-not-published")
    owner_sql("UPDATE equipment_type SET status = 'published' WHERE id = %s", (unit["type"],))
    seed_node = owner_sql(
        "SELECT id FROM location_node WHERE version_id <> %s LIMIT 1",
        (owner_sql("SELECT version_id FROM location_node WHERE id = %s", (unit["bin"],))[0][0],),
    )
    _problem(
        _create(api, unit, _body(unit, location_node_id=str(seed_node[0][0]))),
        409,
        "location-not-published",
    )


async def test_photos_then_confirm_queues_attempt_one(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
) -> None:
    scan = _create(api, unit, _body(unit)).json()
    sid = scan["scan_id"]
    _problem(_put(api, sid, 1, user=DANA), 403, "forbidden")
    _problem(_put(api, sid, 5), 400, "validation")
    _problem(_put(api, sid, 1, body=b"not a jpeg"), 400, "validation")
    bad = _put(api, sid, 1, **{"Content-Digest": _digest(b"other bytes")})
    _problem(bad, 400, "digest-mismatch")
    big = JPEG + b"x" * (2 * 1024 * 1024)
    _problem(_put(api, sid, 1, body=big), 400, "photo-too-large")

    assert _put(api, sid, 2).status_code == 204
    _problem(api.post(f"/scans/{sid}/upload-complete", TARA), 409, "photos-missing")  # no photo 1
    assert _put(api, sid, 1).status_code == 204
    key = f"{TENANT_A}/{unit['bu']}/{sid}/1"
    assert uploads[key] == JPEG
    stored = owner_sql(
        "SELECT object_key, sha256 FROM scan_photo WHERE scan_id = %s AND photo_no = 1", (sid,)
    )
    assert stored[0] == (key, hashlib.sha256(JPEG).hexdigest())

    done = api.post(f"/scans/{sid}/upload-complete", TARA)
    assert done.status_code == 202, done.text
    assert done.json() == {
        "scan_id": sid,
        "record_no": scan["record_no"],
        "attempt_no": 1,
        "processing_status": "extracting",
    }
    again = api.post(f"/scans/{sid}/upload-complete", TARA)  # safe to retry
    assert again.status_code == 202 and again.json() == done.json()
    attempts = owner_sql(
        "SELECT attempt_no, trigger, status FROM extraction_attempt WHERE scan_id = %s", (sid,)
    )
    assert attempts == [(1, "first", "queued")]
    _problem(_put(api, sid, 1), 409, "invalid-state")  # no more photos once confirmed

    # The AI isn't configured in this test: the worker keeps the event and retries it later.
    owner_sql(
        "UPDATE outbox_event SET next_run_at = now() - interval '1 second' WHERE status = 'pending'"
    )

    async def accept(settings: Any, **_: str) -> None:
        return None

    await outbox.run_due(
        pool,
        WorkerSettings(worker_database_url=database["worker"]),  # type: ignore[arg-type]
        send=accept,
        limit=1000,
    )
    event = owner_sql(
        "SELECT status, attempts FROM outbox_event WHERE event_type = 'extraction.run'"
        " AND payload->>'scan_id' = %s",
        (sid,),
    )
    assert event == [("pending", 1)]


def test_a_retake_closes_the_original(api: Api, owner_sql: Any, unit: dict[str, str]) -> None:
    original = _create(api, unit, _body(unit)).json()
    _problem(
        _create(api, unit, _body(unit, retake_of_scan_id=original["scan_id"])), 409, "invalid-state"
    )
    owner_sql(
        "UPDATE scan SET processing_status = 'retake_required' WHERE id = %s",
        (original["scan_id"],),
    )
    _problem(  # only your own scan
        _create(api, unit, _body(unit, retake_of_scan_id=original["scan_id"]), user=DANA),
        409,
        "invalid-state",
    )
    retake = _create(api, unit, _body(unit, retake_of_scan_id=original["scan_id"]))
    assert retake.status_code == 201 and retake.json()["retake_of_scan_id"] == original["scan_id"]
    status = owner_sql("SELECT review_status FROM scan WHERE id = %s", (original["scan_id"],))
    assert status == [("closed",)]


def test_scan_detail_and_who_may_see_it(
    api: Api, owner_sql: Any, unit: dict[str, str], uploads: dict[str, bytes]
) -> None:
    scan = _confirmed(api, unit)
    sid = scan["scan_id"]
    queued = api.get(f"/scans/{sid}", TARA).json()
    assert (queued["processing_status"], queued["attempts_used"], queued["fields"]) == (
        "extracting",
        1,
        [],
    )
    assert queued["latest_attempt"]["status"] == "queued"
    photo = queued["photos"][0]
    assert photo["photo_no"] == 1 and "X-Amz-Expires=900" in photo["view_url"]

    attempt = owner_sql("SELECT id FROM extraction_attempt WHERE scan_id = %s", (sid,))[0][0]
    owner_sql(
        "INSERT INTO ai_field_value (tenant_id, attempt_id, field_definition_id, value,"
        " confidence, flag_reasons) VALUES (%s, %s, %s, 'SN-77', 0.42, '{low_confidence}')",
        (TENANT_A, attempt, unit["fd"]),
    )
    _attempt_ends(owner_sql, sid, "succeeded", "ready_to_review")
    done = api.get(f"/scans/{sid}", TARA).json()
    assert done["fields"][1]["field_key"] == "voltage" and done["fields"][1]["ai_value"] is None
    assert done["fields"][:1] == [
        {
            "field_key": "serial",
            "label": "Serial",
            "data_type": "text",
            "is_required": True,
            "is_critical": False,
            "ai_value": "SN-77",
            "confidence": 0.42,
            "flag_reasons": ["low_confidence"],
        }
    ]
    assert api.get(f"/scans/{sid}", ERIN).status_code == 200  # the EA
    _problem(api.get(f"/scans/{sid}", DANA), 403, "forbidden")  # another technician
    _problem(api.get(f"/scans/{sid}", BO), 404, "not-found")  # an admin of another unit
    batch = owner_sql(
        "INSERT INTO review_batch (tenant_id, bu_id, batch_no, assigned_to, created_by)"
        " VALUES (%s, %s, %s, %s, %s) RETURNING id",
        (TENANT_A, unit["bu"], f"B-T{uuid.uuid4().hex[:6]}", DANA, ERIN),
    )[0][0]
    owner_sql(
        "INSERT INTO review_assignment (tenant_id, batch_id, scan_id, assigned_to)"
        " VALUES (%s, %s, %s, %s)",
        (TENANT_A, batch, sid, DANA),
    )
    assert api.get(f"/scans/{sid}", DANA).status_code == 200  # assigned to review it


def test_retry_re_extract_and_the_three_attempt_limit(
    api: Api, owner_sql: Any, unit: dict[str, str], uploads: dict[str, bytes]
) -> None:
    sid = _confirmed(api, unit)["scan_id"]
    _problem(api.post(f"/scans/{sid}/retry-extraction", TARA, headers=_key()), 409, "invalid-state")
    _attempt_ends(owner_sql, sid, "failed", "failed")
    _problem(api.post(f"/scans/{sid}/retry-extraction", DANA, headers=_key()), 403, "forbidden")
    retried = api.post(f"/scans/{sid}/retry-extraction", TARA, headers=_key())
    assert retried.status_code == 202, retried.text
    assert (retried.json()["attempt_no"], retried.json()["trigger"], retried.json()["status"]) == (
        2,
        "retry",
        "queued",
    )
    assert owner_sql("SELECT processing_status FROM scan WHERE id = %s", (sid,)) == [
        ("extracting",)
    ]

    # The AI saw another label: re-extract as another published type of the unit.
    _attempt_ends(owner_sql, sid, "succeeded", "ready_to_review")
    other = owner_sql(
        "INSERT INTO equipment_type (tenant_id, bu_id, process_id, name, created_via)"
        " SELECT tenant_id, bu_id, process_id, 'Valve', 'blank' FROM equipment_type"
        " WHERE id = %s RETURNING id",
        (unit["type"],),
    )[0][0]
    body = {"equipment_type_id": str(other)}
    _problem(
        api.post(f"/scans/{sid}/re-extract", TARA, headers=_key(), json=body),
        409,
        "type-not-published",
    )
    body = {"equipment_type_id": unit["type"]}
    again = api.post(f"/scans/{sid}/re-extract", TARA, headers=_key(), json=body)
    assert again.status_code == 202 and again.json()["trigger"] == "re_extract", again.text
    assert again.json()["attempt_no"] == 3

    _attempt_ends(owner_sql, sid, "failed", "failed")
    _problem(
        api.post(f"/scans/{sid}/retry-extraction", TARA, headers=_key()), 409, "scan-attempts-used"
    )
    _attempt_ends(owner_sql, sid, "succeeded", "ready_to_review")
    _problem(
        api.post(f"/scans/{sid}/re-extract", TARA, headers=_key(), json=body),
        409,
        "scan-attempts-used",
    )


def test_discard_only_before_submit(api: Api, owner_sql: Any, unit: dict[str, str]) -> None:
    sid = _create(api, unit, _body(unit)).json()["scan_id"]
    _problem(api.post(f"/scans/{sid}/discard", DANA), 403, "forbidden")
    assert api.post(f"/scans/{sid}/discard", TARA).status_code == 204
    assert owner_sql("SELECT review_status FROM scan WHERE id = %s", (sid,)) == [("discarded",)]
    _problem(api.post(f"/scans/{sid}/discard", TARA), 409, "invalid-state")
    submitted = _create(api, unit, _body(unit)).json()["scan_id"]
    owner_sql("UPDATE scan SET review_status = 'waiting_for_approval' WHERE id = %s", (submitted,))
    _problem(api.post(f"/scans/{submitted}/discard", TARA), 409, "invalid-state")
    _problem(api.post(f"/scans/{_id()}/discard", TARA), 404, "not-found")
