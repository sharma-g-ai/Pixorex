"""Review queue, scan review, decisions and override (contracts 3.3-3.7).

A scan's current revision is its highest revision_no; the current decision is the one with
is_current on that revision (one per revision, unique index). An open assignment is a
review_assignment with status 'assigned' (one per scan, unique index)."""

from datetime import date
from typing import Any
from uuid import UUID

from app.core.db import Conn
from app.core.timezone import WEEK_START, from_day, to_day

# The current revision, its current decision and the open assignment of each scan.
_CURRENT = (
    " LEFT JOIN LATERAL (SELECT r.* FROM revision r WHERE r.scan_id = s.id"
    "   ORDER BY r.revision_no DESC LIMIT 1) cr ON true"
    " LEFT JOIN review_decision cd ON cd.revision_id = cr.id AND cd.is_current"
    " LEFT JOIN review_assignment ra ON ra.scan_id = s.id AND ra.status = 'assigned'"
    " LEFT JOIN review_batch rb ON rb.id = ra.batch_id"
    " LEFT JOIN app_user assignee ON assignee.id = ra.assigned_to"
)


# Current decision approved since Monday 00:00 IST: the home card count and its queue tab.
_APPROVED_THIS_WEEK = f"cd.decision = 'approved' AND cd.decided_at >= {WEEK_START}"


async def queue_counts(conn: Conn, bu_id: UUID) -> dict[str, int]:
    cur = await conn.execute(
        "SELECT"
        " count(*) FILTER (WHERE s.review_status = 'waiting_for_approval') AS waiting,"
        " count(*) FILTER (WHERE s.review_status = 'waiting_for_approval'"
        "   AND cr.submitted_at < now() - interval '1 day') AS over_1d,"
        " count(*) FILTER (WHERE s.review_status = 'waiting_for_approval'"
        "   AND cr.submitted_at < now() - interval '7 days') AS over_1w,"
        " count(*) FILTER (WHERE s.review_status = 'waiting_for_approval'"
        "   AND ra.id IS NOT NULL) AS delegated,"
        " count(*) FILTER (WHERE cd.decider_role = 'delegated_technician')"
        "   AS decided_by_technicians,"
        f" count(*) FILTER (WHERE {_APPROVED_THIS_WEEK}) AS approved_this_week"
        f" FROM scan s {_CURRENT} WHERE s.bu_id = %s",
        (bu_id,),
    )
    row = await cur.fetchone()
    return {k: int(v) for k, v in (row or {}).items()}


_WAITING = "s.review_status = 'waiting_for_approval'"
_QUEUE_FILTERS = {
    "waiting": _WAITING,
    "over_1d": f"{_WAITING} AND cr.submitted_at < now() - interval '1 day'",
    "over_1w": f"{_WAITING} AND cr.submitted_at < now() - interval '7 days'",
    "delegated": f"{_WAITING} AND ra.id IS NOT NULL",
    "decided_by_technicians": "cd.decider_role = 'delegated_technician'",
    "approved_this_week": _APPROVED_THIS_WEEK,
}


# One queue row. "status" is what the BU Admin sees: waiting (no decision yet, including scans
# with a delegated technician), approved, or rejected (sent back, not resubmitted yet).
# "date" is the date the Date column shows and filters: when the scan was captured. "waiting_since"
# is when it entered the queue (the Under Review pill's hover time).
_ITEM = (
    "SELECT s.id AS scan_id, s.record_no, et.name AS equipment_type_name,"
    " tech.full_name AS captured_by_name, s.location_path_snapshot AS location_path,"
    " cr.submitted_at AS waiting_since, rb.id AS batch_id, rb.batch_no,"
    " assignee.full_name AS assigned_to_name,"
    " cr.revision_no, cr.origin = 'rejection_fix' AS resubmitted,"
    " approver.full_name AS approved_by_name, decider.full_name AS decided_by_name,"
    " CASE s.review_status WHEN 'waiting_for_approval' THEN 'waiting'"
    "   WHEN 'approved' THEN 'approved' WHEN 'rejected' THEN 'rejected'"
    "   ELSE 'closed' END AS status,"
    " s.captured_at AS date,"
    " (SELECT count(*) FROM revision_field rf JOIN ai_field_value av"
    "    ON av.id = rf.ai_field_value_id"
    "   WHERE rf.revision_id = cr.id AND cardinality(av.flag_reasons) > 0) AS flag_count,"
    " (SELECT count(*) FROM revision_field rf WHERE rf.revision_id = cr.id"
    "   AND rf.verification_state = 'corrected') AS corrected_count,"
    " (SELECT count(*) FROM revision_field rf WHERE rf.revision_id = cr.id"
    "   AND rf.verification_state = 'unreadable') AS unreadable_count"
    f" FROM scan s {_CURRENT}"
    " JOIN equipment_type et ON et.id = s.equipment_type_id"
    " JOIN app_user tech ON tech.id = s.technician_id"
    " LEFT JOIN app_user approver ON approver.id = cd.decided_by AND cd.decision = 'approved'"
    " LEFT JOIN app_user decider ON decider.id = cd.decided_by"
)


async def queue_items(
    conn: Conn, *, bu_id: UUID, filter_: str, after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    """The tab queues (deprecated, kept for older clients): oldest waiting first."""
    keyset = " AND (cr.submitted_at, s.id) > (%s::timestamptz, %s::uuid)" if after else ""
    cur = await conn.execute(
        f"{_ITEM}"
        f" WHERE s.bu_id = %s AND cr.id IS NOT NULL AND {_QUEUE_FILTERS[filter_]}{keyset}"
        " ORDER BY cr.submitted_at, s.id LIMIT %s",
        [bu_id, *(after or []), limit + 1],
    )
    return await cur.fetchall()


# Scan review statuses behind each status the queue offers.
_STATUS_SCANS = {
    "waiting": "waiting_for_approval",
    "approved": "approved",
    "rejected": "rejected",
}


async def queue_page(
    conn: Conn,
    *,
    bu_id: UUID,
    statuses: list[str],
    type_ids: list[UUID] | None,
    captured_by: list[UUID] | None,
    date_from: date | None,
    date_to: date | None,
    decided_from: date | None,
    search: str | None,
    newest_first: bool | None,
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    """The review queue with its header filters: any mix of statuses, schemas and captured-by
    people, and a From/To range on the Date column (whole days, Indian time, both included),
    sorted by that date. With no sort chosen ([newest_first] is None) it is oldest first, with the
    scans a technician holds after the others. [search] finds scans by Scan ID, spaces ignored;
    [decided_from] keeps scans decided from that day (Home's "approved this week")."""
    where = ["q.status = ANY(%s)"]
    params: list[Any] = [statuses]
    if type_ids:
        where.append("q.equipment_type_id = ANY(%s::uuid[])")
        params.append(type_ids)
    if captured_by:
        where.append("q.technician_id = ANY(%s::uuid[])")
        params.append(captured_by)
    if date_from:
        where.append(from_day("q.date"))
        params.append(date_from)
    if date_to:
        where.append(to_day("q.date"))
        params.append(date_to)
    if decided_from:
        where.append(from_day("q.decided_at"))
        params.append(decided_from)
    if search is not None:
        where.append("q.record_no LIKE %s")
        params.append(f"%{''.join(c for c in search if c.isdigit()) or 'x'}%")
    descending = bool(newest_first)
    held_last = newest_first is None
    cmp = "<" if descending else ">"
    if after:
        if held_last:
            where.append(
                f"(q.held, q.date, q.scan_id) {cmp} (%s::boolean, %s::timestamptz, %s::uuid)"
            )
        else:
            where.append(f"(q.date, q.scan_id) {cmp} (%s::timestamptz, %s::uuid)")
        params += after
    order = "DESC" if descending else "ASC"
    sort = f"q.date {order}, q.scan_id {order}"
    if held_last:
        sort = f"q.held, {sort}"
    inner = _ITEM.replace(
        "SELECT s.id AS scan_id,",
        "SELECT s.id AS scan_id, s.equipment_type_id, s.technician_id, cd.decided_at,"
        " (rb.id IS NOT NULL) AS held,",
        1,
    )
    cur = await conn.execute(
        f"SELECT * FROM ({inner}"
        " WHERE s.bu_id = %s AND cr.id IS NOT NULL"
        "   AND s.review_status IN ('waiting_for_approval', 'approved', 'rejected')) q"
        f" WHERE {' AND '.join(where)} ORDER BY {sort} LIMIT %s",
        [bu_id, *params, limit + 1],
    )
    return await cur.fetchall()


async def scan(conn: Conn, scan_id: UUID, *, lock: bool = False) -> dict[str, Any] | None:
    """The scan with its current revision, current decision and open assignment."""
    cur = await conn.execute(
        "SELECT s.id AS scan_id, s.tenant_id, s.bu_id, s.record_no, s.technician_id,"
        " s.review_status, s.contract_id, s.location_path_snapshot AS location_path,"
        " et.name AS equipment_type_name, tech.full_name AS captured_by_name,"
        " cr.id AS revision_id, cr.revision_no, cr.origin, cr.empty_required_fields,"
        " cd.id AS current_decision_id, ra.id AS assignment_id, ra.assigned_to,"
        " ra.batch_id, rb.bu_id AS batch_bu_id"
        f" FROM scan s {_CURRENT}"
        " JOIN equipment_type et ON et.id = s.equipment_type_id"
        " JOIN app_user tech ON tech.id = s.technician_id"
        " WHERE s.id = %s" + (" FOR UPDATE OF s" if lock else ""),
        (scan_id,),
    )
    return await cur.fetchone()


async def had_assignment(conn: Conn, scan_id: UUID, user_id: UUID) -> bool:
    """An assignment that is no longer open (taken back, reassigned...): a stale reviewer."""
    cur = await conn.execute(
        "SELECT 1 FROM review_assignment WHERE scan_id = %s AND assigned_to = %s LIMIT 1",
        (scan_id, user_id),
    )
    return await cur.fetchone() is not None


async def photos(conn: Conn, scan_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT photo_no, object_key FROM scan_photo WHERE scan_id = %s ORDER BY photo_no",
        (scan_id,),
    )
    return await cur.fetchall()


async def review_fields(conn: Conn, contract_id: UUID, revision_id: UUID) -> list[dict[str, Any]]:
    """Every field of the scan's type, in order, with the AI value and the technician's verdict."""
    cur = await conn.execute(
        "SELECT fd.field_key, fd.label, av.value AS ai_value, av.confidence::float AS confidence,"
        " coalesce(av.flag_reasons, '{}') AS flag_reasons, rf.value AS technician_value,"
        " coalesce(rf.verification_state, 'left_empty') AS verification_state,"
        " rf.unreadable_reason, rf.note"
        " FROM extraction_contract ec"
        " JOIN field_definition fd ON fd.type_version_id = ec.type_version_id"
        " LEFT JOIN revision_field rf ON rf.revision_id = %s AND rf.field_key = fd.field_key"
        " LEFT JOIN ai_field_value av ON av.id = rf.ai_field_value_id"
        " WHERE ec.id = %s ORDER BY fd.sort_order, fd.created_at",
        (revision_id, contract_id),
    )
    return await cur.fetchall()


async def decisions(conn: Conn, scan_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT d.id AS decision_id, d.revision_id, d.decision, d.reject_category, d.note,"
        " u.full_name AS decided_by_name, d.decider_role, d.is_current,"
        " d.overrides_decision_id, d.decided_at"
        " FROM review_decision d JOIN revision r ON r.id = d.revision_id"
        " JOIN app_user u ON u.id = d.decided_by"
        " WHERE r.scan_id = %s ORDER BY d.decided_at DESC, d.id DESC",
        (scan_id,),
    )
    return await cur.fetchall()


async def insert_decision(
    conn: Conn,
    *,
    tenant_id: UUID,
    revision_id: UUID,
    decided_by: UUID,
    role: str,
    decision: str,
    reject_category: str | None,
    note: str | None,
    batch_id: UUID | None,
    overrides: UUID | None = None,
) -> UUID:
    cur = await conn.execute(
        "INSERT INTO review_decision (tenant_id, revision_id, decided_by, decider_role, decision,"
        " reject_category, note, batch_id, overrides_decision_id)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING id",
        (
            tenant_id,
            revision_id,
            decided_by,
            role,
            decision,
            reject_category,
            note,
            batch_id,
            overrides,
        ),
    )
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    return UUID(str(row["id"]))


async def set_review_status(conn: Conn, scan_id: UUID, status: str) -> None:
    await conn.execute("UPDATE scan SET review_status = %s WHERE id = %s", (status, scan_id))


async def resolve_escalations(conn: Conn, scan_id: UUID, decision_id: UUID) -> None:
    """The first decision resolves the scan's open escalations (FR-5.8)."""
    await conn.execute(
        "UPDATE escalation SET resolved_by_decision_id = %s, resolved_at = now()"
        " WHERE scan_id = %s AND resolved_at IS NULL",
        (decision_id, scan_id),
    )


async def close_assignment(conn: Conn, assignment_id: UUID, *, decided: bool) -> None:
    """decided: the delegated technician decided it; else an admin decided it first."""
    if decided:
        await conn.execute(
            "UPDATE review_assignment SET status = 'decided' WHERE id = %s", (assignment_id,)
        )
    else:
        await conn.execute(
            "UPDATE review_assignment SET status = 'removed', removed_reason = 'admin_decided',"
            " removed_at = now() WHERE id = %s",
            (assignment_id,),
        )


async def complete_batch_if_done(conn: Conn, batch_id: UUID) -> None:
    """An active batch with nothing left to review is completed."""
    await conn.execute(
        "UPDATE review_batch SET status = 'completed' WHERE id = %s AND status = 'active'"
        " AND NOT EXISTS (SELECT 1 FROM review_assignment WHERE batch_id = %s"
        " AND status = 'assigned')",
        (batch_id, batch_id),
    )


async def decision(conn: Conn, decision_id: UUID, *, lock: bool = False) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT d.id AS decision_id, d.revision_id, d.decided_by, d.decider_role, d.is_current,"
        " d.batch_id, r.scan_id, s.bu_id, s.tenant_id, s.record_no, s.technician_id"
        " FROM review_decision d JOIN revision r ON r.id = d.revision_id"
        " JOIN scan s ON s.id = r.scan_id WHERE d.id = %s" + (" FOR UPDATE OF d" if lock else ""),
        (decision_id,),
    )
    return await cur.fetchone()


async def retire_decision(conn: Conn, decision_id: UUID) -> None:
    await conn.execute(
        "UPDATE review_decision SET is_current = false WHERE id = %s", (decision_id,)
    )


async def technician_decisions(
    conn: Conn,
    *,
    bu_id: UUID,
    decision: str | None,
    decided_by: list[UUID] | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
    newest_first: bool = True,
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    """Decisions made by delegated technicians in the unit, newest first unless
    [newest_first] is false. [date_from]/[date_to]: whole days of Indian time, both included."""
    where: list[str] = ["s.bu_id = %s", "d.decider_role = 'delegated_technician'"]
    params: list[object] = [bu_id]
    if decision:
        where.append("d.decision = %s")
        params.append(decision)
    if decided_by:
        where.append("d.decided_by = ANY(%s::uuid[])")
        params.append(decided_by)
    if date_from:
        where.append(from_day("d.decided_at"))
        params.append(date_from)
    if date_to:
        where.append(to_day("d.decided_at"))
        params.append(date_to)
    if after:
        where.append(
            f"(d.decided_at, d.id) {'<' if newest_first else '>'} (%s::timestamptz, %s::uuid)"
        )
        params += after
    order = "DESC" if newest_first else "ASC"
    cur = await conn.execute(
        "SELECT d.id AS decision_id, s.id AS scan_id, s.record_no, u.full_name AS decided_by_name,"
        " et.name AS equipment_type_name, d.decision, d.reject_category, d.decided_at,"
        " d.batch_id, rb.batch_no,"
        " EXISTS (SELECT 1 FROM review_decision o WHERE o.overrides_decision_id = d.id)"
        "   AS overridden"
        " FROM review_decision d JOIN revision r ON r.id = d.revision_id"
        " JOIN scan s ON s.id = r.scan_id JOIN app_user u ON u.id = d.decided_by"
        " JOIN equipment_type et ON et.id = s.equipment_type_id"
        " LEFT JOIN review_batch rb ON rb.id = d.batch_id"
        f" WHERE {' AND '.join(where)} ORDER BY d.decided_at {order}, d.id {order} LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()
