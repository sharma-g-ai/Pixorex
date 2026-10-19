"""Reading the audit log (contract 3.22) and the caller's notifications (3.19-3.21)."""

from datetime import date
from typing import Any
from uuid import UUID

from app.core.db import Conn


async def audit_page(
    conn: Conn,
    *,
    units: list[UUID] | None,
    bu_id: UUID | None,
    category: str | None,
    since: date | None,
    until: date | None,
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    """Newest first. units=None: every row RLS shows (the EA, tenant-wide rows included)."""
    where: list[str] = ["true"]
    params: list[object] = []
    if units is not None:
        where.append("a.bu_id = ANY(%s)")
        params.append(units)
    if bu_id:
        where.append("a.bu_id = %s")
        params.append(bu_id)
    if category:
        where.append("a.category = %s")
        params.append(category)
    if since:
        where.append("a.occurred_at >= %s::date")
        params.append(since)
    if until:  # inclusive: the whole "to" day
        where.append("a.occurred_at < %s::date + 1")
        params.append(until)
    if after:
        where.append("(a.occurred_at, a.id) < (%s::timestamptz, %s::uuid)")
        params += after
    cur = await conn.execute(
        "SELECT a.id, a.occurred_at, a.actor_type, u.full_name AS actor_name, b.name AS bu_name,"
        " a.category, a.summary, a.action, a.object_type, a.object_id, a.details"
        " FROM audit_log a"
        " LEFT JOIN app_user u ON u.id = a.actor_user_id"
        " LEFT JOIN business_unit b ON b.id = a.bu_id"
        f" WHERE {' AND '.join(where)} ORDER BY a.occurred_at DESC, a.id DESC LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def notifications_page(
    conn: Conn, *, user_id: UUID, unread_only: bool, after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    where: list[str] = ["recipient_user_id = %s"]
    params: list[object] = [user_id]
    if unread_only:
        where.append("read_at IS NULL")
    if after:
        where.append("(created_at, id) < (%s::timestamptz, %s::uuid)")
        params += after
    cur = await conn.execute(
        "SELECT id AS notification_id, kind, title, body, bu_id, object_type, object_id,"
        " created_at, read_at, emailed_at FROM notification"
        f" WHERE {' AND '.join(where)} ORDER BY created_at DESC, id DESC LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def unread_count(conn: Conn, user_id: UUID) -> int:
    cur = await conn.execute(
        "SELECT count(*) AS n FROM notification WHERE recipient_user_id = %s AND read_at IS NULL",
        (user_id,),
    )
    row = await cur.fetchone()
    return int(row["n"]) if row else 0


async def mark_read(conn: Conn, user_id: UUID, notification_id: UUID) -> bool:
    """False: no such notification for this person. Already read stays as it was."""
    cur = await conn.execute(
        "UPDATE notification SET read_at = coalesce(read_at, now())"
        " WHERE id = %s AND recipient_user_id = %s RETURNING id",
        (notification_id, user_id),
    )
    return await cur.fetchone() is not None


async def mark_all_read(conn: Conn, user_id: UUID) -> None:
    await conn.execute(
        "UPDATE notification SET read_at = now() WHERE recipient_user_id = %s AND read_at IS NULL",
        (user_id,),
    )
