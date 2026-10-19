"""Delegated review batches (contracts 3.8-3.14). A batch is a set of review assignments,
never bulk approval (FR-5.6)."""

from typing import Any
from uuid import UUID

from app.core.db import Conn


async def delegates(
    conn: Conn, *, bu_id: UUID, scan_ids: list[UUID], after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    """Technicians of the unit, with their open reviews and own scans in the selection.
    Who may be picked (is_trusted_reviewer) is OPEN O-18, so every technician is listed."""
    keyset = " AND (u.full_name, u.id) > (%(after_name)s, %(after_id)s::uuid)" if after else ""
    cur = await conn.execute(
        "SELECT u.id AS user_id, u.full_name,"
        " (SELECT count(*) FROM review_assignment a JOIN review_batch b ON b.id = a.batch_id"
        "   WHERE a.assigned_to = u.id AND a.status = 'assigned' AND b.bu_id = %(bu)s)"
        "   AS open_review_count,"
        " (SELECT count(*) FROM scan s WHERE s.id = ANY(%(scans)s) AND s.technician_id = u.id)"
        "   AS own_scans_in_selection"
        " FROM app_user u JOIN user_unit_role r ON r.user_id = u.id AND r.bu_id = %(bu)s"
        "  AND r.role = 'field_technician' AND r.removed_at IS NULL"
        f" WHERE u.status <> 'removed'{keyset} ORDER BY u.full_name, u.id LIMIT %(limit)s",
        {
            "bu": bu_id,
            "scans": scan_ids,
            "limit": limit + 1,
            "after_name": after[0] if after else None,
            "after_id": after[1] if after else None,
        },
    )
    return await cur.fetchall()


async def scans_for_batch(conn: Conn, bu_id: UUID, scan_ids: list[UUID]) -> list[dict[str, Any]]:
    """Locks the scans so two batches can't take the same one."""
    cur = await conn.execute(
        "SELECT s.id, s.record_no, s.technician_id, s.review_status,"
        " EXISTS (SELECT 1 FROM review_assignment a WHERE a.scan_id = s.id"
        "   AND a.status = 'assigned') AS assigned"
        " FROM scan s WHERE s.bu_id = %s AND s.id = ANY(%s) FOR UPDATE OF s",
        (bu_id, scan_ids),
    )
    return await cur.fetchall()


async def next_batch_no(conn: Conn, tenant_id: UUID) -> str:
    """Display numbers B-1, B-2... per tenant. Serialised by a transaction-level advisory lock
    on the tenant, so two batches never get the same number."""
    await conn.execute(
        "SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", (f"batch:{tenant_id}",)
    )
    cur = await conn.execute(
        "SELECT coalesce(max(substring(batch_no FROM '^B-([0-9]+)$')::int), 0) + 1 AS n"
        " FROM review_batch WHERE tenant_id = %s",
        (tenant_id,),
    )
    row = await cur.fetchone()
    return f"B-{row['n'] if row else 1}"


async def create_batch(
    conn: Conn, *, tenant_id: UUID, bu_id: UUID, batch_no: str, assigned_to: UUID, created_by: UUID
) -> UUID:
    cur = await conn.execute(
        "INSERT INTO review_batch (tenant_id, bu_id, batch_no, assigned_to, created_by)"
        " VALUES (%s, %s, %s, %s, %s) RETURNING id",
        (tenant_id, bu_id, batch_no, assigned_to, created_by),
    )
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    return UUID(str(row["id"]))


async def assign(
    conn: Conn, *, tenant_id: UUID, batch_id: UUID, scan_ids: list[UUID], assigned_to: UUID
) -> None:
    for scan_id in scan_ids:
        await conn.execute(
            "INSERT INTO review_assignment (tenant_id, batch_id, scan_id, assigned_to)"
            " VALUES (%s, %s, %s, %s)",
            (tenant_id, batch_id, scan_id, assigned_to),
        )


_BATCH = (
    "SELECT b.id AS batch_id, b.bu_id, b.tenant_id, b.batch_no, b.assigned_to, b.status,"
    " b.created_at, b.reminded_at, a.full_name AS assigned_to_name,"
    " c.full_name AS created_by_name,"
    " (SELECT count(DISTINCT x.scan_id) FROM review_assignment x WHERE x.batch_id = b.id)"
    "   AS scan_count,"
    " (SELECT count(DISTINCT x.scan_id) FROM review_assignment x WHERE x.batch_id = b.id"
    "   AND x.status = 'decided') AS decided_count"
    " FROM review_batch b JOIN app_user a ON a.id = b.assigned_to"
    " JOIN app_user c ON c.id = b.created_by"
)


async def batches(
    conn: Conn,
    *,
    bu_id: UUID | None = None,
    assigned_to: UUID | None = None,
    status: str | None,
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    """A unit's batches, or the batches given to one technician."""
    where: list[str] = ["true"]
    params: list[object] = []
    if bu_id is not None:
        where.append("b.bu_id = %s")
        params.append(bu_id)
    if assigned_to is not None:
        where.append("b.assigned_to = %s")
        params.append(assigned_to)
    if status:
        where.append("b.status = %s")
        params.append(status)
    if after:
        where.append("(b.created_at, b.id) < (%s::timestamptz, %s::uuid)")
        params += after
    cur = await conn.execute(
        f"{_BATCH} WHERE {' AND '.join(where)} ORDER BY b.created_at DESC, b.id DESC LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def batch(conn: Conn, batch_id: UUID, *, lock: bool = False) -> dict[str, Any] | None:
    cur = await conn.execute(
        f"{_BATCH} WHERE b.id = %s" + (" FOR UPDATE OF b" if lock else ""), (batch_id,)
    )
    return await cur.fetchone()


async def assignments(conn: Conn, batch_id: UUID) -> list[dict[str, Any]]:
    """The latest assignment of each scan in the batch."""
    cur = await conn.execute(
        "SELECT DISTINCT ON (a.scan_id) a.scan_id, s.record_no, a.status, a.removed_reason"
        " FROM review_assignment a JOIN scan s ON s.id = a.scan_id WHERE a.batch_id = %s"
        " ORDER BY a.scan_id, a.created_at DESC",
        (batch_id,),
    )
    rows = await cur.fetchall()
    return sorted(rows, key=lambda r: r["record_no"])


async def open_assignments(conn: Conn, batch_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT a.id, a.scan_id, s.technician_id FROM review_assignment a"
        " JOIN scan s ON s.id = a.scan_id WHERE a.batch_id = %s AND a.status = 'assigned'",
        (batch_id,),
    )
    return await cur.fetchall()


async def remove_open(conn: Conn, batch_id: UUID, reason: str) -> None:
    await conn.execute(
        "UPDATE review_assignment SET status = 'removed', removed_reason = %s, removed_at = now()"
        " WHERE batch_id = %s AND status = 'assigned'",
        (reason, batch_id),
    )


async def set_assignee(conn: Conn, batch_id: UUID, user_id: UUID) -> None:
    await conn.execute(
        "UPDATE review_batch SET assigned_to = %s WHERE id = %s", (user_id, batch_id)
    )


async def take_back(conn: Conn, batch_id: UUID, message: str | None) -> None:
    await conn.execute(
        "UPDATE review_batch SET status = 'taken_back', take_back_message = %s WHERE id = %s",
        (message, batch_id),
    )


async def remind(conn: Conn, batch_id: UUID) -> Any:
    cur = await conn.execute(
        "UPDATE review_batch SET reminded_at = now() WHERE id = %s RETURNING reminded_at",
        (batch_id,),
    )
    row = await cur.fetchone()
    return row["reminded_at"] if row else None


async def is_technician_of(conn: Conn, user_id: UUID, bu_id: UUID) -> bool:
    cur = await conn.execute(
        "SELECT 1 FROM user_unit_role r JOIN app_user u ON u.id = r.user_id"
        " WHERE r.user_id = %s AND r.bu_id = %s AND r.role = 'field_technician'"
        " AND r.removed_at IS NULL AND u.status <> 'removed'",
        (user_id, bu_id),
    )
    return await cur.fetchone() is not None


async def bu_admin_of(conn: Conn, bu_id: UUID) -> UUID | None:
    cur = await conn.execute("SELECT bu_admin_user_id FROM business_unit WHERE id = %s", (bu_id,))
    row = await cur.fetchone()
    return row["bu_admin_user_id"] if row else None
