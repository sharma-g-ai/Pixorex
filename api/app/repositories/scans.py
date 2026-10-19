"""Scan capture data (contracts 2.21-2.27): scans, photos, extraction attempts, quota."""

import json
from datetime import datetime
from typing import Any
from uuid import UUID

from app.core.db import Conn

EXTRACTION_EVENT = "extraction.run"  # the worker calls the AI proxy for one attempt
PATH_SEPARATOR = " \u203a "  # names joined as on the screens: Plant 07 > Building A > Bin 14

_SCAN = (
    "SELECT s.id AS scan_id, s.tenant_id, s.record_no, s.bu_id, s.client_capture_id,"
    " s.technician_id, s.equipment_type_id, et.name AS equipment_type_name, s.contract_id,"
    " s.location_node_id, s.location_path_snapshot AS location_path, s.processing_status,"
    " s.review_status, s.retake_of_scan_id, s.captured_at"
    " FROM scan s JOIN equipment_type et ON et.id = s.equipment_type_id"
)


async def scan(conn: Conn, scan_id: UUID) -> dict[str, Any] | None:
    cur = await conn.execute(f"{_SCAN} WHERE s.id = %s", (scan_id,))
    return await cur.fetchone()


async def scan_for_update(conn: Conn, scan_id: UUID) -> dict[str, Any] | None:
    """Locks the scan row, so two calls on one scan run one after the other."""
    cur = await conn.execute(f"{_SCAN} WHERE s.id = %s FOR UPDATE OF s", (scan_id,))
    return await cur.fetchone()


async def by_capture_id(
    conn: Conn, tenant_id: UUID, client_capture_id: UUID
) -> dict[str, Any] | None:
    cur = await conn.execute(
        f"{_SCAN} WHERE s.tenant_id = %s AND s.client_capture_id = %s",
        (tenant_id, client_capture_id),
    )
    return await cur.fetchone()


async def lock_capture(conn: Conn, tenant_id: UUID, client_capture_id: UUID) -> None:
    """Serialises two creates with the same client_capture_id (a phone retrying fast)."""
    await conn.execute(
        "SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
        (f"capture:{tenant_id}:{client_capture_id}",),
    )


async def published_type(conn: Conn, bu_id: UUID, type_id: UUID) -> dict[str, Any] | None:
    """The type, published in this unit, with its active extraction contract."""
    cur = await conn.execute(
        "SELECT et.id, et.process_id, c.id AS contract_id FROM equipment_type et"
        " JOIN equipment_type_version v ON v.equipment_type_id = et.id"
        " JOIN extraction_contract c ON c.type_version_id = v.id AND c.status = 'active'"
        " WHERE et.id = %s AND et.bu_id = %s AND et.status = 'published'"
        " ORDER BY c.created_at DESC LIMIT 1",
        (type_id, bu_id),
    )
    return await cur.fetchone()


async def published_node_path(conn: Conn, bu_id: UUID, node_id: UUID) -> str | None:
    """The node's full path, top level first, if it is in the unit's published tree, else
    None (FR-2.6: saved with the scan as it was at capture)."""
    cur = await conn.execute(
        "WITH RECURSIVE up AS ("
        "  SELECT n.id, n.parent_id, n.name, 0 AS depth FROM location_node n"
        "  JOIN location_hierarchy_version v ON v.id = n.version_id"
        "  WHERE n.id = %s AND v.bu_id = %s AND v.status = 'published'"
        "  UNION ALL"
        "  SELECT p.id, p.parent_id, p.name, up.depth + 1 FROM location_node p"
        "  JOIN up ON p.id = up.parent_id)"
        " SELECT string_agg(name, %s ORDER BY depth DESC) AS path FROM up",
        (node_id, bu_id, PATH_SEPARATOR),
    )
    row = await cur.fetchone()
    return row["path"] if row else None


async def next_record_no(conn: Conn, tenant_id: UUID) -> str:
    """Display numbers REC-1, REC-2... per tenant, as batch numbers are. Serialised by a
    transaction-level advisory lock on the tenant, so two scans never get the same number."""
    await conn.execute(
        "SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", (f"record:{tenant_id}",)
    )
    cur = await conn.execute(
        "SELECT coalesce(max(substring(record_no FROM '^REC-([0-9]+)$')::bigint), 0) + 1 AS n"
        " FROM scan WHERE tenant_id = %s",
        (tenant_id,),
    )
    row = await cur.fetchone()
    return f"REC-{row['n'] if row else 1}"


async def insert(
    conn: Conn,
    *,
    tenant_id: UUID,
    bu_id: UUID,
    process_id: UUID,
    record_no: str,
    client_capture_id: UUID,
    technician_id: UUID,
    equipment_type_id: UUID,
    contract_id: UUID,
    location_node_id: UUID,
    location_path: str,
    retake_of_scan_id: UUID | None,
    captured_at: datetime,
) -> UUID:
    cur = await conn.execute(
        "INSERT INTO scan (tenant_id, bu_id, process_id, record_no, client_capture_id,"
        " technician_id, equipment_type_id, contract_id, location_node_id,"
        " location_path_snapshot, retake_of_scan_id, captured_at)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING id",
        (
            tenant_id,
            bu_id,
            process_id,
            record_no,
            client_capture_id,
            technician_id,
            equipment_type_id,
            contract_id,
            location_node_id,
            location_path,
            retake_of_scan_id,
            captured_at,
        ),
    )
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    scan_id: UUID = row["id"]
    return scan_id


async def close(conn: Conn, scan_id: UUID) -> None:
    """A retake replaces this scan: it is closed and stays as history."""
    await conn.execute(
        "UPDATE scan SET review_status = 'closed', updated_at = now() WHERE id = %s", (scan_id,)
    )


async def count_quota(conn: Conn, tenant_id: UUID, bu_id: UUID) -> None:
    """One more accepted scan this month for the unit (FR-6.5). A repeated create of the same
    capture never reaches this, so it never counts twice."""
    await conn.execute(
        "INSERT INTO quota_usage (tenant_id, bu_id, period_month, scans_used)"
        " VALUES (%s, %s, date_trunc('month', now())::date, 1)"
        " ON CONFLICT (bu_id, period_month)"
        " DO UPDATE SET scans_used = quota_usage.scans_used + 1, updated_at = now()",
        (tenant_id, bu_id),
    )


async def photos(conn: Conn, scan_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT photo_no, object_key, sha256 FROM scan_photo WHERE scan_id = %s ORDER BY photo_no",
        (scan_id,),
    )
    return await cur.fetchall()


async def save_photo(
    conn: Conn, *, tenant_id: UUID, scan_id: UUID, photo_no: int, object_key: str, sha256: str
) -> None:
    """Same photo number again replaces it (the phone resending)."""
    await conn.execute(
        "INSERT INTO scan_photo (tenant_id, scan_id, photo_no, object_key, sha256)"
        " VALUES (%s, %s, %s, %s, %s) ON CONFLICT (scan_id, photo_no)"
        " DO UPDATE SET object_key = excluded.object_key, sha256 = excluded.sha256,"
        " updated_at = now()",
        (tenant_id, scan_id, photo_no, object_key, sha256),
    )


async def attempts(conn: Conn, scan_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT id, attempt_no, trigger, status, detected_label, suggested_type_id,"
        " suggestion_confidence::float AS suggestion_confidence FROM extraction_attempt"
        " WHERE scan_id = %s ORDER BY attempt_no",
        (scan_id,),
    )
    return await cur.fetchall()


async def start_attempt(
    conn: Conn, *, tenant_id: UUID, scan_id: UUID, attempt_no: int, contract_id: UUID, trigger: str
) -> UUID:
    """A queued attempt, the scan moved to extracting, and the outbox event for the AI proxy,
    in the caller's transaction (ARCHITECTURE §8)."""
    cur = await conn.execute(
        "INSERT INTO extraction_attempt (tenant_id, scan_id, attempt_no, contract_id, trigger)"
        " VALUES (%s, %s, %s, %s, %s) RETURNING id",
        (tenant_id, scan_id, attempt_no, contract_id, trigger),
    )
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    attempt_id: UUID = row["id"]
    await conn.execute(
        "UPDATE scan SET processing_status = 'extracting', updated_at = now() WHERE id = %s",
        (scan_id,),
    )
    await conn.execute(
        "INSERT INTO outbox_event (tenant_id, event_type, payload) VALUES (%s, %s,"
        " jsonb_build_object('attempt_id', %s::text, 'scan_id', %s::text))",
        (tenant_id, EXTRACTION_EVENT, attempt_id, scan_id),
    )
    return attempt_id


async def ai_fields(conn: Conn, contract_id: UUID, attempt_id: UUID) -> list[dict[str, Any]]:
    """Every field of the contract's type version, in order, with this attempt's AI answer."""
    cur = await conn.execute(
        "SELECT fd.field_key, fd.label, fd.data_type, fd.is_required, fd.is_critical,"
        " av.id AS ai_field_value_id, av.value AS ai_value, av.confidence::float AS confidence,"
        " coalesce(av.flag_reasons, '{}') AS flag_reasons FROM extraction_contract c"
        " JOIN field_definition fd ON fd.type_version_id = c.type_version_id"
        " LEFT JOIN ai_field_value av ON av.field_definition_id = fd.id AND av.attempt_id = %s"
        " WHERE c.id = %s ORDER BY fd.sort_order",
        (attempt_id, contract_id),
    )
    return await cur.fetchall()


async def open_assignee(conn: Conn, scan_id: UUID) -> UUID | None:
    """The technician this scan is assigned to for review right now, if any."""
    cur = await conn.execute(
        "SELECT assigned_to FROM review_assignment WHERE scan_id = %s AND status = 'assigned'",
        (scan_id,),
    )
    row = await cur.fetchone()
    return row["assigned_to"] if row else None


async def set_type(conn: Conn, scan_id: UUID, type_id: UUID, contract_id: UUID) -> None:
    """Re-extract as another type: the scan takes that type and its active contract."""
    await conn.execute(
        "UPDATE scan SET equipment_type_id = %s, contract_id = %s, updated_at = now()"
        " WHERE id = %s",
        (type_id, contract_id, scan_id),
    )


async def discard(conn: Conn, scan_id: UUID) -> None:
    await conn.execute(
        "UPDATE scan SET review_status = 'discarded', updated_at = now() WHERE id = %s",
        (scan_id,),
    )


# Tabs of My Scans (contract 3.1). A scan keeps processing ready_to_review after it is
# submitted, so the processing states count only while the scan is still a draft.
MY_TABS = {
    "needs_action": "((s.review_status = 'draft' AND s.processing_status IN"
    " ('ready_to_review', 'failed', 'retake_required')) OR s.review_status = 'rejected')",
    "in_progress": "((s.review_status = 'draft' AND s.processing_status IN"
    " ('uploading', 'extracting')) OR s.review_status = 'waiting_for_approval')",
    "approved": "s.review_status = 'approved'",
}


async def my_scans(
    conn: Conn,
    *,
    technician_id: UUID,
    filters: dict[str, Any],
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    where: list[str] = ["s.technician_id = %s"]
    params: list[object] = [technician_id]
    if filters.get("tab") in MY_TABS:
        where.append(MY_TABS[filters["tab"]])
    for key, sql in (
        ("bu_id", "s.bu_id = %s"),
        ("review_status", "s.review_status = %s"),
        ("equipment_type_id", "s.equipment_type_id = %s"),
        ("from", "s.captured_at >= %s::date"),
        ("to", "s.captured_at < %s::date + 1"),
    ):
        if filters.get(key):
            where.append(sql)
            params.append(filters[key])
    if filters.get("q"):
        # "Search name, serial or bin": the type name, the submitted values, the location.
        where.append(
            "(et.name ILIKE %s OR s.location_path_snapshot ILIKE %s"
            " OR cr.values_json::text ILIKE %s)"
        )
        q = filters["q"].replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        pattern = f"%{q}%"
        params += [pattern, pattern, pattern]
    if after:
        where.append("(s.updated_at, s.id) < (%s::timestamptz, %s::uuid)")
        params += after
    cur = await conn.execute(
        "SELECT s.id AS scan_id, s.record_no, et.name AS equipment_type_name,"
        " s.location_path_snapshot AS location_path, s.processing_status, s.review_status,"
        " (SELECT count(*) FROM extraction_attempt a WHERE a.scan_id = s.id) AS attempts_used,"
        " CASE WHEN s.review_status = 'rejected' THEN cd.reject_category END AS reject_category,"
        " s.updated_at FROM scan s JOIN equipment_type et ON et.id = s.equipment_type_id"
        " LEFT JOIN LATERAL (SELECT r.id, r.values_json FROM revision r WHERE r.scan_id = s.id"
        "   ORDER BY r.revision_no DESC LIMIT 1) cr ON true"
        " LEFT JOIN review_decision cd ON cd.revision_id = cr.id AND cd.is_current"
        f" WHERE {' AND '.join(where)} ORDER BY s.updated_at DESC, s.id DESC LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def rejected_by(conn: Conn, scan_id: UUID) -> UUID | None:
    """Who rejected the latest revision (a fixed scan goes back to them)."""
    cur = await conn.execute(
        "SELECT cd.decided_by FROM revision r JOIN review_decision cd ON cd.revision_id = r.id"
        " AND cd.is_current WHERE r.scan_id = %s AND cd.decision = 'rejected'"
        " ORDER BY r.revision_no DESC LIMIT 1",
        (scan_id,),
    )
    row = await cur.fetchone()
    return row["decided_by"] if row else None


async def add_revision(
    conn: Conn,
    *,
    tenant_id: UUID,
    scan_id: UUID,
    origin: str,
    values: dict[str, str | None],
    empty_required: list[str],
    submitted_by: UUID,
    resubmit_to: UUID | None,
    fields: list[dict[str, Any]],
) -> dict[str, Any]:
    """The revision, one verdict row per field, and the scan waiting for approval."""
    cur = await conn.execute(
        "INSERT INTO revision (tenant_id, scan_id, revision_no, origin, values_json,"
        " empty_required_fields, submitted_by, resubmit_to_user_id)"
        " VALUES (%s, %s, (SELECT coalesce(max(revision_no), 0) + 1 FROM revision"
        "   WHERE scan_id = %s), %s, %s::jsonb, %s, %s, %s)"
        " RETURNING id AS revision_id, revision_no, origin, empty_required_fields",
        (
            tenant_id,
            scan_id,
            scan_id,
            origin,
            json.dumps(values),
            empty_required,
            submitted_by,
            resubmit_to,
        ),
    )
    revision = await cur.fetchone()
    if revision is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    for f in fields:
        await conn.execute(
            "INSERT INTO revision_field (tenant_id, revision_id, ai_field_value_id, field_key,"
            " value, verification_state, unreadable_reason, note)"
            " VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
            (
                tenant_id,
                revision["revision_id"],
                f["ai_field_value_id"],
                f["field_key"],
                f["value"],
                f["verification_state"],
                f["unreadable_reason"],
                f["note"],
            ),
        )
    await conn.execute(
        "UPDATE scan SET review_status = 'waiting_for_approval', updated_at = now() WHERE id = %s",
        (scan_id,),
    )
    return revision
