"""Escalations (contracts 3.16, 3.17) and the all-scans list (3.18) for the Enterprise Admin."""

from datetime import date
from typing import Any
from uuid import UUID

from app.core.db import Conn


async def escalations(
    conn: Conn,
    *,
    bu_id: UUID | None,
    reason: str | None,
    open_: bool | None,
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    """Oldest escalation first."""
    where: list[str] = ["true"]
    params: list[object] = []
    if bu_id:
        where.append("e.bu_id = %s")
        params.append(bu_id)
    if reason:
        where.append("e.reason = %s")
        params.append(reason)
    if open_ is not None:
        where.append("e.resolved_at IS NULL" if open_ else "e.resolved_at IS NOT NULL")
    if after:
        where.append("(e.escalated_at, e.id) > (%s::timestamptz, %s::uuid)")
        params += after
    cur = await conn.execute(
        "SELECT e.id AS escalation_id, e.scan_id, s.record_no, e.bu_id, b.name AS bu_name,"
        " et.name AS equipment_type_name, tech.full_name AS captured_by_name, e.reason,"
        " e.escalated_at, e.reminded_at, rb.batch_no"
        " FROM escalation e JOIN scan s ON s.id = e.scan_id"
        " JOIN business_unit b ON b.id = e.bu_id"
        " JOIN equipment_type et ON et.id = s.equipment_type_id"
        " JOIN app_user tech ON tech.id = s.technician_id"
        " LEFT JOIN review_assignment ra ON ra.scan_id = s.id AND ra.status = 'assigned'"
        " LEFT JOIN review_batch rb ON rb.id = ra.batch_id"
        f" WHERE {' AND '.join(where)} ORDER BY e.escalated_at, e.id LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def remind_open(conn: Conn, bu_id: UUID) -> int:
    cur = await conn.execute(
        "UPDATE escalation SET reminded_at = now() WHERE bu_id = %s AND resolved_at IS NULL",
        (bu_id,),
    )
    return cur.rowcount


async def scans(
    conn: Conn,
    *,
    bu_id: UUID | None,
    review_status: str | None,
    delegated: bool | None,
    q: str | None,
    since: date | None,
    until: date | None,
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    """Newest capture first. q: record number, type name, technician name, or a value in the
    current revision (the serial number lives there)."""
    where: list[str] = ["true"]
    params: list[object] = []
    if bu_id:
        where.append("s.bu_id = %s")
        params.append(bu_id)
    if review_status:
        where.append("s.review_status = %s")
        params.append(review_status)
    if delegated is not None:
        where.append("ra.id IS NOT NULL" if delegated else "ra.id IS NULL")
    if q:
        where.append(
            "(s.record_no ILIKE %s OR et.name ILIKE %s OR tech.full_name ILIKE %s"
            " OR cr.values_json::text ILIKE %s)"
        )
        like = "%" + q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
        params += [like, like, like, like]
    if since:
        where.append("s.captured_at >= %s::date")
        params.append(since)
    if until:
        where.append("s.captured_at < %s::date + 1")
        params.append(until)
    if after:
        where.append("(s.captured_at, s.id) < (%s::timestamptz, %s::uuid)")
        params += after
    cur = await conn.execute(
        "SELECT s.id AS scan_id, s.record_no, b.name AS bu_name, et.name AS equipment_type_name,"
        " tech.full_name AS captured_by_name, s.location_path_snapshot AS location_path,"
        " s.review_status, s.captured_at,"
        " decider.full_name AS reviewer_name, overridden.full_name AS overrode_name,"
        " rb.batch_no, assignee.full_name AS assigned_to_name,"
        " (SELECT e.reason FROM escalation e WHERE e.scan_id = s.id AND e.resolved_at IS NULL"
        "   ORDER BY e.escalated_at LIMIT 1) AS escalation_reason"
        " FROM scan s JOIN business_unit b ON b.id = s.bu_id"
        " JOIN equipment_type et ON et.id = s.equipment_type_id"
        " JOIN app_user tech ON tech.id = s.technician_id"
        " LEFT JOIN LATERAL (SELECT r.* FROM revision r WHERE r.scan_id = s.id"
        "   ORDER BY r.revision_no DESC LIMIT 1) cr ON true"
        " LEFT JOIN review_decision cd ON cd.revision_id = cr.id AND cd.is_current"
        " LEFT JOIN app_user decider ON decider.id = cd.decided_by"
        " LEFT JOIN review_decision od ON od.id = cd.overrides_decision_id"
        " LEFT JOIN app_user overridden ON overridden.id = od.decided_by"
        " LEFT JOIN review_assignment ra ON ra.scan_id = s.id AND ra.status = 'assigned'"
        " LEFT JOIN review_batch rb ON rb.id = ra.batch_id"
        " LEFT JOIN app_user assignee ON assignee.id = ra.assigned_to"
        f" WHERE {' AND '.join(where)} ORDER BY s.captured_at DESC, s.id DESC LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()
