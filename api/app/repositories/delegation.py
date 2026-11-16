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


# A technician's decision in batch b that a BU Admin replaced (contract 3.7): d is the
# technician's decision, o the one that replaced it.
_OVERRIDDEN = (
    " FROM review_decision d JOIN review_decision o ON o.overrides_decision_id = d.id"
    " JOIN revision r ON r.id = d.revision_id"
    " WHERE d.batch_id = b.id AND d.decider_role = 'delegated_technician'"
)
# ...whose decision_overridden notification is still unread. Notifications are visible to
# their recipient only (RLS), so for anyone but that technician this finds nothing.
_UNSEEN = (
    " AND EXISTS (SELECT 1 FROM notification n WHERE n.kind = 'decision_overridden'"
    "   AND n.recipient_user_id = d.decided_by AND n.object_id = r.scan_id"
    "   AND n.read_at IS NULL AND n.created_at >= o.decided_at)"
)

_BATCH = (
    "SELECT b.id AS batch_id, b.bu_id, b.tenant_id, b.batch_no, b.assigned_to, b.status,"
    " b.created_at, b.reminded_at, a.full_name AS assigned_to_name,"
    " c.full_name AS created_by_name,"
    " (SELECT count(DISTINCT x.scan_id) FROM review_assignment x WHERE x.batch_id = b.id)"
    "   AS scan_count,"
    " (SELECT count(DISTINCT x.scan_id) FROM review_assignment x WHERE x.batch_id = b.id"
    "   AND x.status = 'decided') AS decided_count,"
    " (SELECT count(DISTINCT x.scan_id) FROM review_assignment x WHERE x.batch_id = b.id"
    "   AND x.status = 'assigned') AS open_count,"
    f" (SELECT count(*){_OVERRIDDEN}) AS overridden_count,"
    f" (SELECT count(*){_OVERRIDDEN}{_UNSEEN}) AS overridden_unseen_count"
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
    or_unseen_override: bool = False,
) -> list[dict[str, Any]]:
    """A unit's batches, or the batches given to one technician. With [or_unseen_override],
    a batch in another status is listed too while it has an override not seen yet (T 77)."""
    where: list[str] = ["true"]
    params: list[object] = []
    if bu_id is not None:
        where.append("b.bu_id = %s")
        params.append(bu_id)
    if assigned_to is not None:
        where.append("b.assigned_to = %s")
        params.append(assigned_to)
    if status and or_unseen_override:
        where.append(f"(b.status = %s OR EXISTS (SELECT 1{_OVERRIDDEN}{_UNSEEN}))")
        params.append(status)
    elif status:
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


async def assignments(
    conn: Conn, batch_id: UUID, *, technician: UUID | None = None
) -> list[dict[str, Any]]:
    """The latest assignment of each scan in the batch, with what a row shows (T 74): type,
    who captured it, where, flags, photo 1. With [technician], also that technician's own
    decision in this batch and, if a BU Admin replaced it, the replacing decision (T 77).
    One query: a batch holds at most 50 scans."""
    cur = await conn.execute(
        "SELECT DISTINCT ON (a.scan_id) a.scan_id, s.record_no, a.status, a.removed_reason,"
        " et.name AS equipment_type_name, tech.full_name AS captured_by_name,"
        " s.location_path_snapshot AS location_path,"
        " coalesce(cr.submitted_at, s.captured_at) AS submitted_at,"
        " (SELECT count(*) FROM revision_field rf JOIN ai_field_value av"
        "    ON av.id = rf.ai_field_value_id"
        "   WHERE rf.revision_id = cr.id AND cardinality(av.flag_reasons) > 0) AS flag_count,"
        " (SELECT sp.object_key FROM scan_photo sp WHERE sp.scan_id = s.id"
        "   ORDER BY sp.photo_no LIMIT 1) AS photo_key,"
        " md.decision AS my_decision, md.reject_category AS my_category,"
        " md.decided_at AS my_decided_at,"
        " o.decision AS ov_decision, o.reject_category AS ov_category, o.note AS ov_note,"
        " ob.full_name AS ov_by, o.decided_at AS ov_at,"
        " nn.id AS ov_notification_id, (nn.read_at IS NOT NULL) AS ov_seen"
        " FROM review_assignment a JOIN scan s ON s.id = a.scan_id"
        " JOIN equipment_type et ON et.id = s.equipment_type_id"
        " JOIN app_user tech ON tech.id = s.technician_id"
        " LEFT JOIN LATERAL (SELECT r.id, r.submitted_at FROM revision r WHERE r.scan_id = s.id"
        "   ORDER BY r.revision_no DESC LIMIT 1) cr ON true"
        " LEFT JOIN LATERAL (SELECT d.id, d.decision, d.reject_category, d.decided_at"
        "   FROM review_decision d JOIN revision dr ON dr.id = d.revision_id"
        "   WHERE d.batch_id = a.batch_id AND dr.scan_id = s.id AND d.decided_by = %(me)s"
        "   ORDER BY d.decided_at DESC LIMIT 1) md ON true"
        " LEFT JOIN review_decision o ON o.overrides_decision_id = md.id"
        " LEFT JOIN app_user ob ON ob.id = o.decided_by"
        " LEFT JOIN LATERAL (SELECT n.id, n.read_at FROM notification n"
        "   WHERE n.kind = 'decision_overridden' AND n.recipient_user_id = %(me)s"
        "   AND n.object_id = s.id AND n.created_at >= o.decided_at"
        "   ORDER BY n.created_at LIMIT 1) nn ON o.id IS NOT NULL"
        " WHERE a.batch_id = %(batch)s"
        " ORDER BY a.scan_id, a.created_at DESC",
        {"batch": batch_id, "me": technician},
    )
    rows = await cur.fetchall()
    return sorted(rows, key=_batch_order)


def _batch_order(r: dict[str, Any]) -> tuple[int, float, str]:
    """T 74: still to review first (longest waiting on top), then done (latest decision on
    top), then scans that left the batch."""
    if r["status"] == "assigned":
        return (0, r["submitted_at"].timestamp(), r["record_no"])
    if r["status"] == "decided":
        when = r["my_decided_at"] or r["submitted_at"]
        return (1, -when.timestamp(), r["record_no"])
    return (2, 0.0, r["record_no"])


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
