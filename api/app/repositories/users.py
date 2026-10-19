"""app_user, user_unit_role and user_session queries. RLS applies to every one."""

from typing import Any
from uuid import UUID

from app.core.db import Conn
from app.repositories.rows import returned_id


async def profile(conn: Conn, user_id: UUID) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT u.id, u.full_name, u.email, u.phone_number, u.status, u.last_bu_id,"
        " t.name AS tenant_name"
        " FROM app_user u JOIN tenant t ON t.id = u.tenant_id WHERE u.id = %s",
        (user_id,),
    )
    return await cur.fetchone()


async def unit_roles(conn: Conn, user_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT r.bu_id, bu.name, r.role, r.is_primary, a.full_name AS assigned_by_name"
        " FROM user_unit_role r"
        " LEFT JOIN business_unit bu ON bu.id = r.bu_id"
        " LEFT JOIN app_user a ON a.id = r.assigned_by"
        " WHERE r.user_id = %s AND r.removed_at IS NULL"
        " ORDER BY r.is_primary DESC, bu.name NULLS FIRST",
        (user_id,),
    )
    return await cur.fetchall()


async def mark_seen(conn: Conn, user_id: UUID) -> None:
    """last_active_at, and the first sign-in turns an invited account active (D-08)."""
    await conn.execute(
        "UPDATE app_user SET last_active_at = now(),"
        " status = CASE WHEN status = 'invited' THEN 'active' ELSE status END WHERE id = %s",
        (user_id,),
    )


async def live_session(conn: Conn, user_id: UUID, device_id: str) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT id, active_bu_id FROM user_session"
        " WHERE user_id = %s AND device_id = %s AND revoked_at IS NULL",
        (user_id, device_id),
    )
    return await cur.fetchone()


async def open_session(
    conn: Conn, *, tenant_id: UUID, user_id: UUID, device_id: str, bu_id: UUID | None
) -> None:
    await conn.execute(
        "INSERT INTO user_session (tenant_id, user_id, device_id, active_bu_id, last_seen_at)"
        " VALUES (%s, %s, %s, %s, now())"
        " ON CONFLICT (user_id, device_id) WHERE revoked_at IS NULL DO NOTHING",
        (tenant_id, user_id, device_id, bu_id),
    )


async def touch_session(conn: Conn, session_id: UUID) -> None:
    await conn.execute("UPDATE user_session SET last_seen_at = now() WHERE id = %s", (session_id,))


async def set_active_unit(conn: Conn, user_id: UUID, device_id: str, bu_id: UUID) -> None:
    await conn.execute(
        "UPDATE user_session SET active_bu_id = %s, last_seen_at = now()"
        " WHERE user_id = %s AND device_id = %s AND revoked_at IS NULL",
        (bu_id, user_id, device_id),
    )
    await conn.execute("UPDATE app_user SET last_bu_id = %s WHERE id = %s", (bu_id, user_id))


async def revoke_session(conn: Conn, user_id: UUID, device_id: str) -> None:
    await conn.execute(
        "UPDATE user_session SET revoked_at = now()"
        " WHERE user_id = %s AND device_id = %s AND revoked_at IS NULL",
        (user_id, device_id),
    )


async def by_email(conn: Conn, email: str) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT id, status FROM app_user WHERE lower(email) = lower(%s)", (email,)
    )
    return await cur.fetchone()


async def create_invited(
    conn: Conn, *, tenant_id: UUID, email: str, full_name: str, phone: str | None
) -> UUID:
    cur = await conn.execute(
        "INSERT INTO app_user (tenant_id, email, full_name, phone_number, status)"
        " VALUES (%s, %s, %s, %s, 'invited') RETURNING id",
        (tenant_id, email, full_name, phone),
    )
    return await returned_id(cur)


async def reinvite(conn: Conn, user_id: UUID, full_name: str, phone: str | None) -> None:
    """An existing person accepts again: new name, new phone (technicians), removed -> invited.
    A phone stays verified unless the number changes. (SET reads the row's old values.)
    """
    await conn.execute(
        "UPDATE app_user SET full_name = %(name)s,"
        " phone_number = coalesce(%(phone)s, phone_number),"
        " phone_verified_at = CASE WHEN %(phone)s::text IS NULL OR %(phone)s = phone_number"
        " THEN phone_verified_at END,"
        " status = CASE WHEN status = 'removed' THEN 'invited' ELSE status END WHERE id = %(id)s",
        {"name": full_name, "phone": phone, "id": user_id},
    )


async def set_keycloak_id(conn: Conn, user_id: UUID, keycloak_user_id: str) -> None:
    await conn.execute(
        "UPDATE app_user SET keycloak_user_id = %s WHERE id = %s", (keycloak_user_id, user_id)
    )


async def active_roles_in(conn: Conn, bu_ids: list[UUID], role: str) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT user_id, bu_id FROM user_unit_role"
        " WHERE bu_id = ANY(%s) AND role = %s AND removed_at IS NULL",
        (bu_ids, role),
    )
    return await cur.fetchall()


async def has_primary(conn: Conn, user_id: UUID) -> bool:
    cur = await conn.execute(
        "SELECT 1 FROM user_unit_role WHERE user_id = %s AND is_primary AND removed_at IS NULL",
        (user_id,),
    )
    return await cur.fetchone() is not None


async def add_role(
    conn: Conn,
    *,
    tenant_id: UUID,
    user_id: UUID,
    bu_id: UUID,
    role: str,
    is_primary: bool,
    assigned_by: UUID,
) -> None:
    """No-op when the person already holds an active role in that unit."""
    await conn.execute(
        "INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role, is_primary, assigned_by)"
        " VALUES (%s, %s, %s, %s, %s, %s)"
        " ON CONFLICT (user_id, bu_id) WHERE removed_at IS NULL DO NOTHING",
        (tenant_id, user_id, bu_id, role, is_primary, assigned_by),
    )


async def units_with_role(conn: Conn, user_id: UUID, role: str) -> set[UUID]:
    cur = await conn.execute(
        "SELECT bu_id FROM user_unit_role WHERE user_id = %s AND role = %s AND removed_at IS NULL",
        (user_id, role),
    )
    return {r["bu_id"] for r in await cur.fetchall()}


async def other_roles_in(conn: Conn, user_id: UUID, bu_ids: list[UUID], role: str) -> list[UUID]:
    """Units where the person already holds a different active role."""
    cur = await conn.execute(
        "SELECT bu_id FROM user_unit_role WHERE user_id = %s AND bu_id = ANY(%s)"
        " AND role <> %s AND removed_at IS NULL",
        (user_id, bu_ids, role),
    )
    return [r["bu_id"] for r in await cur.fetchall()]


async def remove_roles(conn: Conn, user_id: UUID, bu_ids: list[UUID], role: str) -> list[UUID]:
    """Ends the roles (history kept). The 0002 trigger clears business_unit.bu_admin_user_id."""
    cur = await conn.execute(
        "UPDATE user_unit_role SET removed_at = now(), is_primary = false"
        " WHERE user_id = %s AND bu_id = ANY(%s) AND role = %s AND removed_at IS NULL"
        " RETURNING bu_id",
        (user_id, bu_ids, role),
    )
    return [r["bu_id"] for r in await cur.fetchall()]


async def active_role_count(conn: Conn, user_id: UUID) -> int:
    cur = await conn.execute(
        "SELECT count(*) AS n FROM user_unit_role WHERE user_id = %s AND removed_at IS NULL",
        (user_id,),
    )
    row = await cur.fetchone()
    return int(row["n"]) if row else 0


async def ensure_primary(conn: Conn, user_id: UUID) -> None:
    """After a removal, the oldest remaining role becomes primary if none is."""
    await conn.execute(
        "UPDATE user_unit_role SET is_primary = true WHERE id = ("
        " SELECT id FROM user_unit_role WHERE user_id = %(u)s AND removed_at IS NULL"
        " ORDER BY created_at LIMIT 1)"
        " AND NOT EXISTS (SELECT 1 FROM user_unit_role WHERE user_id = %(u)s"
        " AND is_primary AND removed_at IS NULL)",
        {"u": user_id},
    )


async def mark_removed(conn: Conn, user_id: UUID) -> None:
    await conn.execute("UPDATE app_user SET status = 'removed' WHERE id = %s", (user_id,))


async def revoke_sessions(conn: Conn, user_id: UUID, bu_id: UUID | None = None) -> None:
    """All live sessions, or only those working in one unit."""
    await conn.execute(
        "UPDATE user_session SET revoked_at = now()"
        " WHERE user_id = %s AND revoked_at IS NULL AND (%s::uuid IS NULL OR active_bu_id = %s)",
        (user_id, bu_id, bu_id),
    )
