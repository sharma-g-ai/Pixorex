"""business_unit queries. RLS limits a BU Admin to their own units; the EA sees all."""

from typing import Any
from uuid import UUID

from app.core.db import Conn
from app.repositories.rows import returned_id

_UNIT = (
    "SELECT bu.id AS bu_id, bu.name, bu.facility_name, a.id AS admin_id,"
    " a.full_name AS admin_name, coalesce(l.status, 'not_published') AS locations_status,"
    " (SELECT count(*) FROM scan s WHERE s.bu_id = bu.id"
    "   AND s.review_status = 'waiting_for_approval') AS waiting_count,"
    " (SELECT count(*) FROM escalation e WHERE e.bu_id = bu.id"
    "   AND e.resolved_at IS NULL) AS escalated_count,"
    " (SELECT count(*) FROM review_assignment ra JOIN review_batch rb ON rb.id = ra.batch_id"
    "   WHERE rb.bu_id = bu.id AND ra.status = 'assigned') AS delegated_count,"
    " (SELECT count(*) FROM user_unit_role t WHERE t.bu_id = bu.id"
    "   AND t.role = 'field_technician' AND t.removed_at IS NULL) AS technician_count,"
    " (SELECT count(*) FROM scan s WHERE s.bu_id = bu.id"
    "   AND s.created_at >= date_trunc('month', now())) AS scans_this_month,"
    # Vacant: since the last BU Admin left, or since the unit was created (canvas EA 28).
    " CASE WHEN bu.bu_admin_user_id IS NULL"
    "   THEN coalesce(prev.removed_at, bu.created_at) END AS vacant_since,"
    " prev.user_id AS prev_id, prev.full_name AS prev_name"
    " FROM business_unit bu"
    " LEFT JOIN app_user a ON a.id = bu.bu_admin_user_id"
    " LEFT JOIN LATERAL (SELECT r.removed_at, r.user_id, u.full_name FROM user_unit_role r"
    "   JOIN app_user u ON u.id = r.user_id WHERE bu.bu_admin_user_id IS NULL"
    "   AND r.bu_id = bu.id AND r.role = 'bu_admin' AND r.removed_at IS NOT NULL"
    "   ORDER BY r.removed_at DESC LIMIT 1) prev ON true"
    " LEFT JOIN location_hierarchy_version l ON l.bu_id = bu.id"
)


async def page(
    conn: Conn, *, units: list[UUID] | None, vacant_only: bool, after: list[str] | None, limit: int
) -> list[dict[str, Any]]:
    """units=None: every unit RLS shows (the EA)."""
    where: list[str] = ["true"]
    params: list[object] = []
    if units is not None:
        where.append("bu.id = ANY(%s)")
        params.append(units)
    if vacant_only:
        where.append("bu.bu_admin_user_id IS NULL")
    if after:
        where.append("(bu.name, bu.id) > (%s, %s::uuid)")
        params += after
    cur = await conn.execute(
        f"{_UNIT} WHERE {' AND '.join(where)} ORDER BY bu.name, bu.id LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def one(conn: Conn, bu_id: UUID) -> dict[str, Any] | None:
    cur = await conn.execute(f"{_UNIT} WHERE bu.id = %s", (bu_id,))
    return await cur.fetchone()


async def create(conn: Conn, *, tenant_id: UUID, name: str, facility: str) -> UUID:
    """The unit, its default process and its unpublished location tree (contract 1.13)."""
    cur = await conn.execute(
        "INSERT INTO business_unit (tenant_id, name, facility_name, status)"
        " VALUES (%s, %s, %s, 'active') RETURNING id",
        (tenant_id, name, facility),
    )
    bu_id = await returned_id(cur)
    await conn.execute(
        "INSERT INTO business_process (tenant_id, bu_id, name, is_default)"
        " VALUES (%s, %s, 'Default', true)",
        (tenant_id, bu_id),
    )
    await conn.execute(
        "INSERT INTO location_hierarchy_version (tenant_id, bu_id) VALUES (%s, %s)",
        (tenant_id, bu_id),
    )
    return bu_id


async def is_bu_admin(conn: Conn, user_id: UUID) -> bool:
    cur = await conn.execute(
        "SELECT 1 FROM user_unit_role"
        " WHERE user_id = %s AND role = 'bu_admin' AND removed_at IS NULL",
        (user_id,),
    )
    return await cur.fetchone() is not None


async def admins_page(
    conn: Conn, *, after: list[str] | None, limit: int, user_id: UUID | None = None
) -> list[dict[str, Any]]:
    """People holding an active bu_admin role, with their units (or just one person)."""
    keyset, params = "", []
    if after:
        keyset = " AND (u.full_name, u.id) > (%s, %s::uuid)"
        params = after
    if user_id:
        keyset += " AND u.id = %s"
        params = [*params, str(user_id)]
    cur = await conn.execute(
        "SELECT u.id AS user_id, u.full_name, u.email, u.status, u.last_active_at,"
        " json_agg(json_build_object('bu_id', bu.id, 'name', bu.name) ORDER BY bu.name) AS units"
        " FROM app_user u"
        " JOIN user_unit_role r ON r.user_id = u.id AND r.role = 'bu_admin'"
        " AND r.removed_at IS NULL"
        " JOIN business_unit bu ON bu.id = r.bu_id"
        f" WHERE true{keyset}"
        " GROUP BY u.id ORDER BY u.full_name, u.id LIMIT %s",
        [*params, limit + 1],
    )
    return await cur.fetchall()


async def all_visible(conn: Conn, bu_ids: list[UUID]) -> bool:
    """Every id is a unit of this tenant the caller may see (RLS)."""
    cur = await conn.execute(
        "SELECT count(*) AS n FROM business_unit WHERE id = ANY(%s)", (bu_ids,)
    )
    row = await cur.fetchone()
    return row is not None and int(row["n"]) == len(set(bu_ids))
