"""The worker against PostgreSQL as the pixorex_worker role: scheduled jobs and the outbox."""

import smtplib
import uuid
from typing import Any

from app.workers import jobs, outbox
from app.workers.settings import WorkerSettings
from tests.integration.conftest import Api
from tests.integration.helpers import BO, ERIN, TARA, THEO
from tests.integration.scans import waiting_scan
from tests.integration.test_s2_identity import P04, P11


def _key() -> dict[str, str]:
    return {"Idempotency-Key": str(uuid.uuid4())}


def _count(owner_sql: Any, sql: str, *params: Any) -> int:
    return int(owner_sql(sql, params)[0][0])


def _settings(database: dict[str, str]) -> WorkerSettings:
    return WorkerSettings(worker_database_url=database["worker"])  # type: ignore[arg-type]


def _make_due(owner_sql: Any) -> None:
    owner_sql(
        "UPDATE outbox_event SET next_run_at = now() - interval '1 second' WHERE status = 'pending'"
    )


async def test_scans_waiting_24h_escalate_once(pool: Any, owner_sql: Any) -> None:
    old = waiting_scan(owner_sql, TARA, hours_waiting=30)
    fresh = waiting_scan(owner_sql, TARA)
    vacant = waiting_scan(owner_sql, TARA, hours_waiting=30, bu=P11)  # Plant 11: no BU Admin
    await jobs.run_all(pool)
    ids = [old["scan_id"], fresh["scan_id"], vacant["scan_id"]]
    reasons = dict(
        owner_sql(
            "SELECT scan_id::text, reason FROM escalation"
            " WHERE scan_id = ANY(%s::uuid[]) AND resolved_at IS NULL",
            (ids,),
        )
    )
    assert reasons == {old["scan_id"]: "not_approved_24h", vacant["scan_id"]: "no_bu_admin"}
    told = (
        "SELECT count(*) FROM notification"
        " WHERE recipient_user_id = %s AND kind = %s AND object_id = %s"
    )
    assert _count(owner_sql, told, ERIN, "scans_escalated", P04) >= 1
    system = (
        "SELECT count(*) FROM audit_log"
        " WHERE actor_type = 'system' AND category = %s AND bu_id = %s"
    )
    assert _count(owner_sql, system, "escalation", P04) >= 1
    await jobs.run_all(pool)  # again: nothing new
    assert (
        _count(owner_sql, "SELECT count(*) FROM escalation WHERE scan_id = %s", old["scan_id"]) == 1
    )


async def test_waiting_alerts_reach_the_bu_admin_once_per_threshold(
    pool: Any, owner_sql: Any
) -> None:
    week = waiting_scan(owner_sql, TARA, hours_waiting=24 * 8)
    await jobs.run_all(pool)
    await jobs.run_all(pool)
    kinds = [
        r[0]
        for r in owner_sql(
            "SELECT kind FROM notification WHERE object_id = %s AND recipient_user_id = %s"
            " ORDER BY kind",
            (week["scan_id"], BO),
        )
    ]
    assert kinds == ["scan_waiting_1d", "scan_waiting_1w"]


async def test_a_stuck_batch_alerts_whoever_delegated_it(
    pool: Any, api: Api, owner_sql: Any
) -> None:
    scan = waiting_scan(owner_sql, TARA)
    batch = api.post(
        f"/business-units/{P04}/review-batches",
        BO,
        headers=_key(),
        json={"assigned_to": THEO, "scan_ids": [scan["scan_id"]]},
    ).json()
    owner_sql(
        "UPDATE review_batch SET created_at = now() - interval '2 days' WHERE id = %s",
        (batch["batch_id"],),
    )
    await jobs.run_all(pool)
    await jobs.run_all(pool)
    alerts = (
        "SELECT count(*) FROM notification WHERE object_id = %s AND kind = %s"
        " AND recipient_user_id = %s"
    )
    assert _count(owner_sql, alerts, batch["batch_id"], "batch_no_progress", BO) == 1
    flags = owner_sql(
        "SELECT alert_1d_at IS NOT NULL, alert_1w_at IS NULL FROM review_batch WHERE id = %s",
        (batch["batch_id"],),
    )
    assert flags[0] == (True, True)


async def test_expired_invites_are_marked_and_their_sender_told(
    pool: Any, api: Api, owner_sql: Any
) -> None:
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
    owner_sql(
        "UPDATE invite SET expires_at = now() - interval '1 minute' WHERE bu_id = %s", (unit,)
    )
    await jobs.run_all(pool)
    await jobs.run_all(pool)
    assert owner_sql("SELECT status FROM invite WHERE bu_id = %s", (unit,))[0][0] == "expired"
    told = (
        "SELECT count(*) FROM notification WHERE kind = 'invite_expired'"
        " AND bu_id = %s AND recipient_user_id = %s"
    )
    assert _count(owner_sql, told, unit, ERIN) == 1


async def test_the_outbox_emails_each_notification_once(
    pool: Any, api: Api, owner_sql: Any, database: dict[str, str]
) -> None:
    scan = waiting_scan(owner_sql, TARA)
    api.post(
        f"/scans/{scan['scan_id']}/decisions", BO, headers=_key(), json={"decision": "approved"}
    )
    note = owner_sql(
        "SELECT id FROM notification WHERE object_id = %s AND kind = 'scan_approved'",
        (scan["scan_id"],),
    )[0][0]
    sent: list[dict[str, str]] = []

    async def fake_send(settings: Any, *, to: str, subject: str, text: str) -> None:
        sent.append({"to": to, "subject": subject, "text": text})

    _make_due(owner_sql)
    await outbox.run_due(pool, _settings(database), send=fake_send, limit=1000)
    mine = [s for s in sent if s["subject"] == f"{scan['record_no']} was approved"]
    assert len(mine) == 1 and mine[0]["to"] == "tech1@demo.local"
    assert "Open Pixorex: http://localhost:5173" in mine[0]["text"]
    assert owner_sql("SELECT emailed_at IS NOT NULL FROM notification WHERE id = %s", (note,))[0][0]
    _make_due(owner_sql)
    await outbox.run_due(pool, _settings(database), send=fake_send, limit=1000)
    assert len([s for s in sent if s["subject"] == f"{scan['record_no']} was approved"]) == 1


async def test_failed_sends_back_off_then_fail(
    pool: Any, api: Api, owner_sql: Any, database: dict[str, str]
) -> None:
    async def accept(settings: Any, **_: str) -> None:
        return None

    _make_due(owner_sql)
    await outbox.run_due(pool, _settings(database), send=accept, limit=1000)  # empty the queue
    scan = waiting_scan(owner_sql, TARA)
    api.post(
        f"/scans/{scan['scan_id']}/decisions", BO, headers=_key(), json={"decision": "approved"}
    )

    async def refuse(settings: Any, **_: str) -> None:
        raise smtplib.SMTPAuthenticationError(451, b"Maximum credits exceeded")

    for attempt in range(1, outbox.MAX_ATTEMPTS + 1):
        _make_due(owner_sql)
        await outbox.run_due(pool, _settings(database), send=refuse, limit=1000)
        status, attempts, later = owner_sql(
            "SELECT status, attempts, next_run_at > now() FROM outbox_event"
            " WHERE payload->>'notification_id' = (SELECT id::text FROM notification"
            " WHERE object_id = %s AND kind = 'scan_approved')",
            (scan["scan_id"],),
        )[0]
        assert attempts == attempt
        assert status == ("failed" if attempt == outbox.MAX_ATTEMPTS else "pending")
        assert later
