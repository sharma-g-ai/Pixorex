"""Equipment types, their single version and fields (contracts 2.10-2.19).
The baseline trigger refuses field changes once the type is published (PX001)."""

import json
from typing import Any
from uuid import UUID

from app.core.db import Conn
from app.repositories.rows import returned_id

_TYPE = (
    "SELECT t.id AS type_id, t.bu_id, t.name, t.status, t.created_via, t.copied_from_type_id,"
    " v.id AS version_id, v.version_no, v.published_at,"
    " (SELECT count(*) FROM field_definition f WHERE f.type_version_id = v.id) AS field_count"
    " FROM equipment_type t JOIN equipment_type_version v ON v.equipment_type_id = t.id"
)
_FIELD = (
    "SELECT id AS field_id, field_key, label, data_type, options, is_required, is_critical,"
    " sort_order, format_rule, is_unique_in_unit, flag_below_confidence::float AS"
    " flag_below_confidence, origin FROM field_definition"
)


async def page(
    conn: Conn, *, bu_id: UUID, status: str | None, after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    where, params = ["t.bu_id = %s"], [str(bu_id)]
    if status:
        where.append("t.status = %s")
        params.append(status)
    if after:
        where.append("(t.name, t.id) > (%s, %s::uuid)")
        params += after
    cur = await conn.execute(
        f"{_TYPE} WHERE {' AND '.join(where)} ORDER BY t.name, t.id LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def one(conn: Conn, type_id: UUID, *, lock: bool = False) -> dict[str, Any] | None:
    cur = await conn.execute(
        f"{_TYPE} WHERE t.id = %s" + (" FOR UPDATE OF t" if lock else ""), (type_id,)
    )
    return await cur.fetchone()


async def fields(conn: Conn, version_ids: list[UUID]) -> dict[UUID, list[dict[str, Any]]]:
    cur = await conn.execute(
        f"{_FIELD.replace('SELECT ', 'SELECT type_version_id, ', 1)}"
        " WHERE type_version_id = ANY(%s) ORDER BY sort_order, created_at",
        (version_ids,),
    )
    grouped: dict[UUID, list[dict[str, Any]]] = {v: [] for v in version_ids}
    for row in await cur.fetchall():
        grouped[row.pop("type_version_id")].append(row)
    return grouped


async def field(conn: Conn, field_id: UUID, version_id: UUID) -> dict[str, Any] | None:
    cur = await conn.execute(
        f"{_FIELD} WHERE id = %s AND type_version_id = %s", (field_id, version_id)
    )
    return await cur.fetchone()


async def default_process(conn: Conn, bu_id: UUID) -> UUID | None:
    cur = await conn.execute(
        "SELECT id FROM business_process WHERE bu_id = %s AND is_default", (bu_id,)
    )
    row = await cur.fetchone()
    return UUID(str(row["id"])) if row else None


async def create(
    conn: Conn,
    *,
    tenant_id: UUID,
    bu_id: UUID,
    process_id: UUID,
    name: str,
    created_via: str,
    copied_from: UUID | None,
) -> UUID:
    """The type and its version 1; returns the version id."""
    cur = await conn.execute(
        "INSERT INTO equipment_type (tenant_id, bu_id, process_id, name, created_via,"
        " copied_from_type_id) VALUES (%s, %s, %s, %s, %s, %s) RETURNING id",
        (tenant_id, bu_id, process_id, name, created_via, copied_from),
    )
    type_id = await returned_id(cur)
    cur = await conn.execute(
        "INSERT INTO equipment_type_version (tenant_id, equipment_type_id) VALUES (%s, %s)"
        " RETURNING id",
        (tenant_id, type_id),
    )
    await returned_id(cur)
    return type_id


async def rename(conn: Conn, type_id: UUID, name: str) -> None:
    await conn.execute("UPDATE equipment_type SET name = %s WHERE id = %s", (name, type_id))


async def delete(conn: Conn, type_id: UUID) -> None:
    """The version and fields go with it (ON DELETE CASCADE, contract 2.14)."""
    await conn.execute("DELETE FROM equipment_type WHERE id = %s", (type_id,))


async def keys_and_order(conn: Conn, version_id: UUID) -> tuple[set[str], int]:
    cur = await conn.execute(
        "SELECT field_key, sort_order FROM field_definition WHERE type_version_id = %s",
        (version_id,),
    )
    rows = await cur.fetchall()
    return {r["field_key"] for r in rows}, max((r["sort_order"] for r in rows), default=0)


async def add_field(
    conn: Conn, *, tenant_id: UUID, version_id: UUID, values: dict[str, Any]
) -> UUID:
    cur = await conn.execute(
        "INSERT INTO field_definition (tenant_id, type_version_id, field_key, label, data_type,"
        " options, is_required, is_critical, sort_order, format_rule, is_unique_in_unit,"
        " flag_below_confidence, origin) VALUES (%(tenant)s, %(version)s, %(field_key)s,"
        " %(label)s, %(data_type)s, %(options)s::jsonb, %(is_required)s, %(is_critical)s,"
        " %(sort_order)s, %(format_rule)s, %(is_unique_in_unit)s, %(flag_below_confidence)s,"
        " %(origin)s) RETURNING id",
        {**values, "options": _json(values["options"]), "tenant": tenant_id, "version": version_id},
    )
    return await returned_id(cur)


async def update_field(conn: Conn, field_id: UUID, values: dict[str, Any]) -> None:
    await conn.execute(
        "UPDATE field_definition SET field_key = %(field_key)s, label = %(label)s,"
        " data_type = %(data_type)s, options = %(options)s::jsonb, is_required = %(is_required)s,"
        " is_critical = %(is_critical)s, format_rule = %(format_rule)s,"
        " is_unique_in_unit = %(is_unique_in_unit)s,"
        " flag_below_confidence = %(flag_below_confidence)s WHERE id = %(id)s",
        {**values, "options": _json(values["options"]), "id": field_id},
    )


async def delete_field(conn: Conn, field_id: UUID) -> None:
    await conn.execute("DELETE FROM field_definition WHERE id = %s", (field_id,))


async def set_order(conn: Conn, version_id: UUID, field_ids: list[UUID]) -> None:
    for order, field_id in enumerate(field_ids, start=1):
        await conn.execute(
            "UPDATE field_definition SET sort_order = %s WHERE id = %s AND type_version_id = %s",
            (order, field_id, version_id),
        )


async def current_prompt_version(conn: Conn) -> UUID | None:
    """Platform-owned and global (FR-3.5): the newest one is current."""
    cur = await conn.execute("SELECT id FROM prompt_version ORDER BY created_at DESC LIMIT 1")
    row = await cur.fetchone()
    return UUID(str(row["id"])) if row else None


async def publish(
    conn: Conn, *, tenant_id: UUID, type_id: UUID, version_id: UUID, prompt_id: UUID, user_id: UUID
) -> dict[str, Any]:
    """Freezes version 1 and binds it to the prompt in an active extraction contract."""
    await conn.execute("UPDATE equipment_type SET status = 'published' WHERE id = %s", (type_id,))
    cur = await conn.execute(
        "UPDATE equipment_type_version SET published_by = %s, published_at = now()"
        " WHERE id = %s RETURNING published_at",
        (user_id, version_id),
    )
    published = await cur.fetchone()
    contract = await returned_id(
        await conn.execute(
            "INSERT INTO extraction_contract (tenant_id, type_version_id, prompt_version_id)"
            " VALUES (%s, %s, %s) RETURNING id",
            (tenant_id, version_id, prompt_id),
        )
    )
    if published is None:
        raise RuntimeError("publish updated no version")
    return {"published_at": published["published_at"], "contract_id": contract}


def _json(value: Any) -> str | None:
    return None if value is None else json.dumps(value)
