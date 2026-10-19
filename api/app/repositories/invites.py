"""invite queries. One row per unit; the rows of one invite share token_hash."""

from datetime import datetime
from typing import Any
from uuid import UUID

from app.core.db import Conn
from app.repositories.rows import returned_id

_ROWS = (
    "SELECT i.id, i.tenant_id, i.bu_id, i.email, i.role, i.status, i.token_hash, i.invited_by,"
    " i.expires_at, i.created_at, bu.name AS bu_name, a.full_name AS invited_by_name"
    " FROM invite i JOIN business_unit bu ON bu.id = i.bu_id JOIN app_user a ON a.id = i.invited_by"
)
# "expired" is not stored when the 24 hours pass; it is worked out on read.
_EFFECTIVE_STATUS = (
    "CASE WHEN i.status = 'pending' AND i.expires_at <= now() THEN 'expired' ELSE i.status END"
)


async def by_token(conn: Conn, token_hash: str, *, lock: bool = False) -> list[dict[str, Any]]:
    sql = f"{_ROWS} WHERE i.token_hash = %s ORDER BY i.created_at, i.id"
    cur = await conn.execute(sql + (" FOR UPDATE OF i" if lock else ""), (token_hash,))
    return await cur.fetchall()


async def other_pending(conn: Conn, email: str, role: str, token_hash: str) -> list[dict[str, Any]]:
    """The same person's other live invites for the same role (accept takes them too, D-09)."""
    cur = await conn.execute(
        f"{_ROWS} WHERE lower(i.email) = lower(%s) AND i.role = %s AND i.token_hash <> %s"
        " AND i.status = 'pending' AND i.expires_at > now() ORDER BY i.created_at FOR UPDATE OF i",
        (email, role, token_hash),
    )
    return await cur.fetchall()


async def group_of(conn: Conn, invite_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        f"{_ROWS} WHERE i.token_hash = (SELECT token_hash FROM invite WHERE id = %s)"
        " ORDER BY i.created_at, i.id FOR UPDATE OF i",
        (invite_id,),
    )
    return await cur.fetchall()


async def insert(
    conn: Conn,
    *,
    tenant_id: UUID,
    bu_id: UUID,
    email: str,
    role: str,
    token_hash: str,
    invited_by: UUID,
    expires_at: datetime,
) -> UUID:
    cur = await conn.execute(
        "INSERT INTO invite (tenant_id, bu_id, email, role, token_hash, invited_by, expires_at)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id",
        (tenant_id, bu_id, email, role, token_hash, invited_by, expires_at),
    )
    return await returned_id(cur)


async def set_status(conn: Conn, ids: list[UUID], status: str) -> None:
    accepted = ", accepted_at = now()" if status == "accepted" else ""
    await conn.execute(f"UPDATE invite SET status = %s{accepted} WHERE id = ANY(%s)", (status, ids))


async def renew(conn: Conn, ids: list[UUID], token_hash: str, expires_at: datetime) -> None:
    """New link: the old token stops working (contract 1.10)."""
    await conn.execute(
        "UPDATE invite SET token_hash = %s, status = 'pending', expires_at = %s WHERE id = ANY(%s)",
        (token_hash, expires_at, ids),
    )


async def page(
    conn: Conn,
    *,
    role: str,
    units: list[UUID] | None,
    status: str | None,
    bu_id: UUID | None,
    after: list[str] | None,
    limit: int,
) -> list[dict[str, Any]]:
    """One row per invite (token), newest first. units=None: every unit RLS shows."""
    where: list[str] = ["i.role = %s"]
    params: list[object] = [role]
    if units is not None:
        where.append("i.bu_id = ANY(%s)")
        params.append(units)
    if bu_id:
        where.append("i.bu_id = %s")
        params.append(bu_id)
    having = f" HAVING min({_EFFECTIVE_STATUS}) = %s" if status else ""
    having_params = [status] if status else []
    keyset, keyset_params = "", []
    if after:
        keyset = " WHERE (g.created_at, g.invite_id) < (%s::timestamptz, %s::uuid)"
        keyset_params = after
    cur = await conn.execute(
        "SELECT * FROM ("
        " SELECT (array_agg(i.id ORDER BY i.created_at, i.id))[1] AS invite_id,"
        f" min(i.email) AS email, min(i.role) AS role, min({_EFFECTIVE_STATUS}) AS status,"
        " min(i.created_at) AS created_at, max(i.expires_at) AS expires_at,"
        " min(a.full_name) AS invited_by_name,"
        " json_agg(json_build_object('bu_id', i.bu_id, 'name', bu.name) ORDER BY bu.name) AS units"
        " FROM invite i JOIN business_unit bu ON bu.id = i.bu_id"
        " JOIN app_user a ON a.id = i.invited_by"
        f" WHERE {' AND '.join(where)} GROUP BY i.token_hash{having}"
        f") g{keyset} ORDER BY g.created_at DESC, g.invite_id DESC LIMIT %s",
        [*params, *having_params, *keyset_params, limit + 1],
    )
    return await cur.fetchall()


async def cancel_pending_for_units(conn: Conn, bu_ids: list[UUID], role: str) -> list[UUID]:
    """Contract 1.16: giving a unit to a BU Admin cancels that unit's pending invites."""
    cur = await conn.execute(
        "UPDATE invite SET status = 'cancelled'"
        " WHERE bu_id = ANY(%s) AND role = %s AND status = 'pending' RETURNING id",
        (bu_ids, role),
    )
    return [r["id"] for r in await cur.fetchall()]
