"""Review queue, scan review, decisions and override (contracts 3.3-3.7).

A scan's current revision is its highest revision_no; the current decision is the one with
is_current on that revision (one per revision, unique index). An open assignment is a
review_assignment with status 'assigned' (one per scan, unique index)."""

from typing import Any
from uuid import UUID

from app.core.db import Conn

# The current revision, its current decision and the open assignment of each scan.
_CURRENT = (
    " LEFT JOIN LATERAL (SELECT r.* FROM revision r WHERE r.scan_id = s.id"
    "   ORDER BY r.revision_no DESC LIMIT 1) cr ON true"
    " LEFT JOIN review_decision cd ON cd.revision_id = cr.id AND cd.is_current"
    " LEFT JOIN review_assignment ra ON ra.scan_id = s.id AND ra.status = 'assigned'"
    " LEFT JOIN review_batch rb ON rb.id = ra.batch_id"
    " LEFT JOIN app_user assignee ON assignee.id = ra.assigned_to"
)


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
        " count(*) FILTER (WHERE cd.decision = 'approved'"
        "   AND cd.decided_at >= date_trunc('week', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')"
        "   AS approved_this_week"
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
}


async def queue_items(
    conn: Conn, *, bu_id: UUID, filter_: str, after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    """Oldest waiting first."""
    keyset = " AND (cr.submitted_at, s.id) > (%s::timestamptz, %s::uuid)" if after else ""
    cur = await conn.execute(
        "SELECT s.id AS scan_id, s.record_no, et.name AS equipment_type_name,"
        " tech.full_name AS captured_by_name, s.location_path_snapshot AS location_path,"
        " cr.submitted_at AS waiting_since, rb.batch_no, assignee.full_name AS assigned_to_name,"
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
        f" WHERE s.bu_id = %s AND cr.id IS NOT NULL AND {_QUEUE_FILTERS[filter_]}{keyset}"
        " ORDER BY cr.submitted_at, s.id LIMIT %s",
        [bu_id, *(after or []), limit + 1],
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
    conn: Conn, *, bu_id: UUID, decision: str | None, after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    """Decisions made by delegated technicians in the unit, newest first."""
    where: list[str] = ["s.bu_id = %s", "d.decider_role = 'delegated_technician'"]
    params: list[object] = [bu_id]
    if decision:
        where.append("d.decision = %s")
        params.append(decision)
    if after:
        where.append("(d.decided_at, d.id) < (%s::timestamptz, %s::uuid)")
        params += after
    cur = await conn.execute(
        "SELECT d.id AS decision_id, s.id AS scan_id, s.record_no, u.full_name AS decided_by_name,"
        " d.decision, d.reject_category, d.decided_at,"
        " EXISTS (SELECT 1 FROM review_decision o WHERE o.overrides_decision_id = d.id)"
        "   AS overridden"
        " FROM review_decision d JOIN revision r ON r.id = d.revision_id"
        " JOIN scan s ON s.id = r.scan_id JOIN app_user u ON u.id = d.decided_by"
        f" WHERE {' AND '.join(where)} ORDER BY d.decided_at DESC, d.id DESC LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()
