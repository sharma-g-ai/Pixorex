"""CSV export data (contracts 4.1, 4.2): scan rows, audit rows and export jobs."""

import json
from typing import Any
from uuid import UUID

from app.core.db import Conn

BUILD_EVENT = "export.build"  # the worker builds files over 1,000 rows


def _scan_where(
    units: list[UUID] | None, filters: dict[str, Any]
) -> tuple[list[str], list[object]]:
    where: list[str] = ["true"]
    params: list[object] = []
    if units is not None:
        where.append("s.bu_id = ANY(%s)")
        params.append(units)
    for key, sql in (
        ("bu_id", "s.bu_id = %s"),
        ("review_status", "s.review_status = %s"),
        ("equipment_type_id", "s.equipment_type_id = %s"),
    ):
        if filters.get(key):
            where.append(sql)
            params.append(filters[key])
    if filters.get("from"):
        where.append("s.captured_at >= %s::date")
        params.append(filters["from"])
    if filters.get("to"):
        where.append("s.captured_at < %s::date + 1")
        params.append(filters["to"])
    return where, params


async def count_scans(conn: Conn, units: list[UUID] | None, filters: dict[str, Any]) -> int:
    where, params = _scan_where(units, filters)
    cur = await conn.execute(
        f"SELECT count(*) AS n FROM scan s WHERE {' AND '.join(where)}", params
    )
    row = await cur.fetchone()
    return int(row["n"]) if row else 0


async def scans(
    conn: Conn, units: list[UUID] | None, filters: dict[str, Any], limit: int | None
) -> list[dict[str, Any]]:
    where, params = _scan_where(units, filters)
    cur = await conn.execute(
        "SELECT s.id, s.record_no, b.name AS unit, s.location_path_snapshot AS location,"
        " et.name AS equipment_type, tech.full_name AS captured_by, s.captured_at,"
        " s.review_status, cr.values_json, cd.decision, cd.reject_category,"
        " decider.full_name AS decided_by, cd.decided_at"
        " FROM scan s JOIN business_unit b ON b.id = s.bu_id"
        " JOIN equipment_type et ON et.id = s.equipment_type_id"
        " JOIN app_user tech ON tech.id = s.technician_id"
        " LEFT JOIN LATERAL (SELECT r.* FROM revision r WHERE r.scan_id = s.id"
        "   ORDER BY r.revision_no DESC LIMIT 1) cr ON true"
        " LEFT JOIN review_decision cd ON cd.revision_id = cr.id AND cd.is_current"
        " LEFT JOIN app_user decider ON decider.id = cd.decided_by"
        f" WHERE {' AND '.join(where)} ORDER BY s.captured_at DESC, s.id DESC LIMIT %s",
        [*params, limit],
    )
    return await cur.fetchall()


async def ai_values(conn: Conn, scan_ids: list[UUID]) -> dict[UUID, dict[str, dict[str, Any]]]:
    """Per scan and field key: the AI value and confidence behind the current revision."""
    cur = await conn.execute(
        "SELECT r.scan_id, rf.field_key, av.value, av.confidence::float AS confidence"
        " FROM revision r JOIN revision_field rf ON rf.revision_id = r.id"
        " LEFT JOIN ai_field_value av ON av.id = rf.ai_field_value_id"
        " WHERE r.scan_id = ANY(%s) AND r.revision_no = (SELECT max(x.revision_no)"
        "   FROM revision x WHERE x.scan_id = r.scan_id)",
        (scan_ids,),
    )
    out: dict[UUID, dict[str, dict[str, Any]]] = {}
    for row in await cur.fetchall():
        out.setdefault(row["scan_id"], {})[row["field_key"]] = row
    return out


def _audit_where(
    units: list[UUID] | None, filters: dict[str, Any]
) -> tuple[list[str], list[object]]:
    where: list[str] = ["true"]
    params: list[object] = []
    if units is not None:
        where.append("a.bu_id = ANY(%s)")
        params.append(units)
    if filters.get("bu_id"):
        where.append("a.bu_id = %s")
        params.append(filters["bu_id"])
    if filters.get("category"):
        where.append("a.category = %s")
        params.append(filters["category"])
    if filters.get("from"):
        where.append("a.occurred_at >= %s::date")
        params.append(filters["from"])
    if filters.get("to"):
        where.append("a.occurred_at < %s::date + 1")
        params.append(filters["to"])
    return where, params


async def count_audit(conn: Conn, units: list[UUID] | None, filters: dict[str, Any]) -> int:
    where, params = _audit_where(units, filters)
    cur = await conn.execute(
        f"SELECT count(*) AS n FROM audit_log a WHERE {' AND '.join(where)}", params
    )
    row = await cur.fetchone()
    return int(row["n"]) if row else 0


async def audit(
    conn: Conn, units: list[UUID] | None, filters: dict[str, Any], limit: int | None
) -> list[dict[str, Any]]:
    where, params = _audit_where(units, filters)
    cur = await conn.execute(
        "SELECT a.occurred_at, u.full_name AS who, b.name AS unit, a.category, a.summary,"
        " a.action, a.object_type, a.object_id FROM audit_log a"
        " LEFT JOIN app_user u ON u.id = a.actor_user_id"
        " LEFT JOIN business_unit b ON b.id = a.bu_id"
        f" WHERE {' AND '.join(where)} ORDER BY a.occurred_at DESC, a.id DESC LIMIT %s",
        [*params, limit],
    )
    return await cur.fetchall()


async def create_job(
    conn: Conn,
    *,
    tenant_id: UUID,
    bu_id: UUID | None,
    user_id: UUID,
    kind: str,
    filters: dict[str, Any],
    options: dict[str, Any],
    row_count: int,
) -> dict[str, Any]:
    cur = await conn.execute(
        "INSERT INTO export_job (tenant_id, bu_id, requested_by, export_kind, filters_json,"
        " options_json, row_count) VALUES (%s, %s, %s, %s, %s::jsonb, %s::jsonb, %s)"
        " RETURNING id AS export_id, export_kind, status, row_count, link_expires_at, file_key",
        (
            tenant_id,
            bu_id,
            user_id,
            kind,
            json.dumps(filters, default=str),
            json.dumps(options),
            row_count,
        ),
    )
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    await conn.execute(
        "INSERT INTO outbox_event (tenant_id, event_type, payload)"
        " VALUES (%s, %s, jsonb_build_object('export_id', %s::text))",
        (tenant_id, BUILD_EVENT, row["export_id"]),
    )
    return row


async def job(conn: Conn, export_id: UUID) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT id AS export_id, export_kind, status, row_count, link_expires_at, file_key,"
        " requested_by FROM export_job WHERE id = %s",
        (export_id,),
    )
    return await cur.fetchone()


async def job_to_build(conn: Conn, export_id: UUID) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT j.id, j.tenant_id, j.bu_id, j.requested_by, j.export_kind, j.filters_json,"
        " j.options_json, u.status AS requester_status FROM export_job j"
        " JOIN app_user u ON u.id = j.requested_by"
        " WHERE j.id = %s AND j.status = 'queued' FOR UPDATE OF j",
        (export_id,),
    )
    return await cur.fetchone()


async def roles_of(conn: Conn, user_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT bu_id, role FROM user_unit_role WHERE user_id = %s AND removed_at IS NULL",
        (user_id,),
    )
    return await cur.fetchall()


async def mark_ready(conn: Conn, export_id: UUID, file_key: str, row_count: int) -> None:
    """The link works for 1 hour from now (PRD FR-6.4)."""
    await conn.execute(
        "UPDATE export_job SET status = 'ready', file_key = %s, row_count = %s,"
        " link_expires_at = now() + interval '1 hour', updated_at = now() WHERE id = %s",
        (file_key, row_count, export_id),
    )


async def mark_failed(conn: Conn, export_id: UUID) -> None:
    await conn.execute(
        "UPDATE export_job SET status = 'failed', updated_at = now()"
        " WHERE id = %s AND status = 'queued'",
        (export_id,),
    )


async def user_names(conn: Conn) -> list[str]:
    """The company's people, so their names can be masked wherever they appear."""
    cur = await conn.execute("SELECT full_name FROM app_user WHERE full_name <> ''")
    return [r["full_name"] for r in await cur.fetchall()]


async def photo_keys(conn: Conn, scan_ids: list[UUID]) -> dict[UUID, list[str]]:
    """Each scan's photo files, in photo order."""
    cur = await conn.execute(
        "SELECT scan_id, object_key FROM scan_photo WHERE scan_id = ANY(%s)"
        " ORDER BY scan_id, photo_no",
        (scan_ids,),
    )
    out: dict[UUID, list[str]] = {}
    for row in await cur.fetchall():
        out.setdefault(row["scan_id"], []).append(row["object_key"])
    return out
