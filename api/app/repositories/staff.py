"""Technicians of a unit (contract 1.18) and their open review assignments."""

from typing import Any
from uuid import UUID

from app.core.db import Conn


async def technicians_page(
    conn: Conn, *, bu_id: UUID, after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    keyset = " AND (u.full_name, u.id) > (%(after_name)s, %(after_id)s::uuid)" if after else ""
    cur = await conn.execute(
        "SELECT u.id AS user_id, u.full_name, u.email, u.status, u.last_active_at,"
        " (SELECT json_agg(json_build_object('bu_id', b.id, 'name', b.name) ORDER BY b.name)"
        "    FROM user_unit_role o JOIN business_unit b ON b.id = o.bu_id"
        "   WHERE o.user_id = u.id AND o.role = 'field_technician' AND o.removed_at IS NULL"
        " ) AS units,"
        " (SELECT count(*) FROM scan s WHERE s.technician_id = u.id AND s.bu_id = %(bu)s"
        "    AND s.created_at >= date_trunc('month', now())) AS scans_this_month,"
        " (SELECT rb.batch_no FROM review_batch rb WHERE rb.assigned_to = u.id"
        "    AND rb.bu_id = %(bu)s AND rb.status = 'active'"
        "   ORDER BY rb.created_at DESC LIMIT 1) AS active_batch_no"
        " FROM app_user u"
        " JOIN user_unit_role r ON r.user_id = u.id AND r.bu_id = %(bu)s"
        "  AND r.role = 'field_technician' AND r.removed_at IS NULL"
        f" WHERE true{keyset}"
        " ORDER BY u.full_name, u.id LIMIT %(limit)s",
        {
            "bu": bu_id,
            "limit": limit + 1,
            "after_name": after[0] if after else None,
            "after_id": after[1] if after else None,
        },
    )
    return await cur.fetchall()


async def release_assignments(conn: Conn, *, user_id: UUID, bu_id: UUID, reason: str) -> int:
    """Open assignments of this person in this unit end; the scans go back to the queue."""
    cur = await conn.execute(
        "UPDATE review_assignment a SET status = 'removed', removed_reason = %s,"
        " removed_at = now()"
        " FROM review_batch b"
        " WHERE b.id = a.batch_id AND b.bu_id = %s AND a.assigned_to = %s"
        " AND a.status = 'assigned'",
        (reason, bu_id, user_id),
    )
    return cur.rowcount
