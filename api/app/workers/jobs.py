"""Scheduled jobs (ARCHITECTURE §8). Each runs per tenant, inside that tenant's RLS context,
and is safe to repeat: what it already did is never done twice.

- escalate: a scan waiting 24 h for approval escalates to the EA (FR-5.8, contract 3.16).
- waiting alerts: the BU Admin hears about a scan waiting 1 day and 1 week.
- batch alerts: a delegated batch with no decision for 1 day / 1 week (FR-5.7).
- expire invites: a pending invite past its 24 h becomes expired; its sender hears (FR-1.4).
"""

from collections import defaultdict
from typing import Any
from uuid import UUID

import structlog

from app.auth.context import set_context
from app.core.db import Conn, Pool
from app.repositories import audit, idempotency
from app.repositories.notifications import notify

_log = structlog.get_logger("pixorex.worker.jobs")
_CURRENT_SUBMIT = (
    "JOIN LATERAL (SELECT r.submitted_at FROM revision r WHERE r.scan_id = s.id"
    " ORDER BY r.revision_no DESC LIMIT 1) cr ON true"
)


async def _enterprise_admins(conn: Conn) -> list[UUID]:
    cur = await conn.execute(
        "SELECT DISTINCT r.user_id FROM user_unit_role r JOIN app_user u ON u.id = r.user_id"
        " WHERE r.role = 'enterprise_admin' AND r.removed_at IS NULL AND u.status <> 'removed'"
    )
    return [r["user_id"] for r in await cur.fetchall()]


def _scans(n: int) -> str:
    return f"{n} {'scan' if n == 1 else 'scans'}"


async def escalate(conn: Conn, tenant_id: UUID) -> int:
    """Scans waiting over 24 h without an open escalation: no_bu_admin when the unit has none,
    else not_approved_24h. A fixed and resubmitted scan can escalate again."""
    cur = await conn.execute(
        "INSERT INTO escalation (tenant_id, bu_id, scan_id, reason)"
        " SELECT s.tenant_id, s.bu_id, s.id,"
        "  CASE WHEN b.bu_admin_user_id IS NULL THEN 'no_bu_admin' ELSE 'not_approved_24h' END"
        f" FROM scan s JOIN business_unit b ON b.id = s.bu_id {_CURRENT_SUBMIT}"
        " WHERE s.review_status = 'waiting_for_approval'"
        "  AND cr.submitted_at < now() - interval '24 hours'"
        "  AND NOT EXISTS (SELECT 1 FROM escalation e WHERE e.scan_id = s.id"
        "                  AND e.resolved_at IS NULL)"
        " RETURNING bu_id, (SELECT name FROM business_unit WHERE id = bu_id) AS bu_name"
    )
    rows = await cur.fetchall()
    per_unit: dict[tuple[UUID, str], int] = defaultdict(int)
    for row in rows:
        per_unit[(row["bu_id"], row["bu_name"])] += 1
    admins = await _enterprise_admins(conn) if per_unit else []
    for (bu_id, bu_name), count in per_unit.items():
        for ea in admins:
            await notify(
                conn,
                tenant_id=tenant_id,
                recipient=ea,
                kind="scans_escalated",
                title=f"{_scans(count)} escalated in {bu_name}",
                body="Not approved within 24 hours.",
                object_type="business_unit",
                object_id=bu_id,
                bu_id=bu_id,
            )
        await audit.record(
            conn,
            tenant_id=tenant_id,
            actor_user_id=None,
            bu_id=bu_id,
            category="escalation",
            action="scan.escalated",
            summary=f"Escalated {_scans(count)} not approved within 24 hours",
            object_type="business_unit",
            object_id=bu_id,
        )
    return len(rows)


async def waiting_alerts(conn: Conn, tenant_id: UUID) -> int:
    """One alert per scan and threshold to the unit's BU Admin. Notifications are visible
    only to their recipient (RLS), so the "already told?" check runs as each BU Admin."""
    cur = await conn.execute(
        "SELECT id AS bu_id, bu_admin_user_id AS admin FROM business_unit"
        " WHERE bu_admin_user_id IS NOT NULL"
    )
    sent = 0
    for unit in await cur.fetchall():
        await set_context(conn, tenant_id=tenant_id, user_id=unit["admin"], is_ea=True)
        for kind, age, words in (
            ("scan_waiting_1d", "1 day", "a day"),
            ("scan_waiting_1w", "7 days", "a week"),
        ):
            due = await conn.execute(
                "SELECT s.id, s.record_no"
                f" FROM scan s {_CURRENT_SUBMIT}"
                " WHERE s.bu_id = %s AND s.review_status = 'waiting_for_approval'"
                f"  AND cr.submitted_at < now() - interval '{age}'"
                "  AND NOT EXISTS (SELECT 1 FROM notification n WHERE n.object_id = s.id"
                "                  AND n.kind = %s AND n.recipient_user_id = %s)",
                (unit["bu_id"], kind, unit["admin"]),
            )
            for row in await due.fetchall():
                await notify(
                    conn,
                    tenant_id=tenant_id,
                    recipient=unit["admin"],
                    kind=kind,
                    title=f"{row['record_no']} has waited over {words} for approval",
                    object_type="scan",
                    object_id=row["id"],
                    bu_id=unit["bu_id"],
                )
                sent += 1
    return sent


async def batch_alerts(conn: Conn, tenant_id: UUID) -> int:
    """An active batch with no decision since it was created, at 1 day and 1 week; the
    alert timestamp stops repeats (FR-5.7). Goes to whoever delegated it."""
    sent = 0
    for column, age, words in (
        ("alert_1d_at", "1 day", "a day"),
        ("alert_1w_at", "7 days", "a week"),
    ):
        cur = await conn.execute(
            f"UPDATE review_batch b SET {column} = now()"
            f" WHERE b.status = 'active' AND b.{column} IS NULL"
            f"  AND b.created_at < now() - interval '{age}'"
            "  AND NOT EXISTS (SELECT 1 FROM review_assignment a WHERE a.batch_id = b.id"
            "                  AND a.status = 'decided')"
            " RETURNING b.id, b.bu_id, b.batch_no, b.created_by"
        )
        for row in await cur.fetchall():
            await notify(
                conn,
                tenant_id=tenant_id,
                recipient=row["created_by"],
                kind="batch_no_progress",
                title=f"{row['batch_no']} has had no decisions for {words}",
                object_type="review_batch",
                object_id=row["id"],
                bu_id=row["bu_id"],
            )
            sent += 1
    return sent


async def expire_invites(conn: Conn, tenant_id: UUID) -> int:
    """Pending invites past their 24 h become expired; one alert per invite to its sender."""
    cur = await conn.execute(
        "UPDATE invite SET status = 'expired' WHERE status = 'pending' AND expires_at <= now()"
        " RETURNING id, token_hash, bu_id, email, invited_by"
    )
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in await cur.fetchall():
        groups[row["token_hash"]].append(row)
    for rows in groups.values():
        first = rows[0]
        await notify(
            conn,
            tenant_id=tenant_id,
            recipient=first["invited_by"],
            kind="invite_expired",
            title=f"The invite to {first['email']} expired",
            body="Send a new invite from the pending invites list.",
            object_type="invite",
            object_id=first["id"],
            bu_id=first["bu_id"],
        )
    return len(groups)


async def expire_idempotency_keys(conn: Conn, tenant_id: UUID) -> int:
    """Stored Idempotency-Keys are kept 24 hours (migration 0003); RLS limits this to the
    tenant."""
    return await idempotency.delete_expired(conn)


JOBS = (escalate, waiting_alerts, batch_alerts, expire_invites, expire_idempotency_keys)


async def run_all(pool: Pool) -> dict[str, int]:
    """Every job for every tenant; one transaction per tenant and job, so one failure
    doesn't undo the rest."""
    async with pool.connection() as conn:
        tenants = [r["id"] for r in await (await conn.execute("SELECT id FROM tenant")).fetchall()]
    totals: dict[str, int] = defaultdict(int)
    for tenant_id in tenants:
        for job in JOBS:
            try:
                async with pool.connection() as conn, conn.transaction():
                    # The worker acts for the whole tenant (all units), like the EA.
                    await set_context(conn, tenant_id=tenant_id, is_ea=True)
                    totals[job.__name__] += await job(conn, tenant_id)
            except Exception:
                _log.exception("job_failed", job=job.__name__, tenant_id=str(tenant_id))
    return dict(totals)
