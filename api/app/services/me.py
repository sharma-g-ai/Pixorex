from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from psycopg import Connection

from app.models.me import Me, UnitRole


def load_unit_roles(conn: Connection, user_id: UUID, *, bypass_rls: bool = False) -> list[dict]:
    # bypass_rls flag kept for call-site clarity; RLS here is tenant-scoped only.
    rows = conn.execute(
        """
        SELECT uur.bu_id, bu.name AS bu_name, uur.role, uur.is_primary,
               assigner.full_name AS assigned_by_name
          FROM user_unit_role uur
          LEFT JOIN business_unit bu ON bu.id = uur.bu_id AND bu.tenant_id = uur.tenant_id
          LEFT JOIN app_user assigner ON assigner.id = uur.assigned_by AND assigner.tenant_id = uur.tenant_id
         WHERE uur.user_id = %s AND uur.removed_at IS NULL
         ORDER BY uur.is_primary DESC, bu.name NULLS FIRST
        """,
        (str(user_id),),
    ).fetchall()
    return list(rows)


def get_me(conn: Connection, *, app_user_id: UUID, tenant_id: UUID, device_id: str) -> Me:
    user = conn.execute(
        """
        SELECT u.id, u.full_name, u.email, u.phone_number, u.status, u.last_bu_id,
               t.name AS tenant_name
          FROM app_user u
          JOIN tenant t ON t.id = u.tenant_id
         WHERE u.id = %s AND u.tenant_id = %s
        """,
        (str(app_user_id), str(tenant_id)),
    ).fetchone()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"title": "Unauthorized", "detail": "Unknown user"},
        )
    if user["status"] == "removed":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"title": "Forbidden", "detail": "Account removed"},
        )

    roles = load_unit_roles(conn, app_user_id)
    units = [
        UnitRole(
            bu_id=r["bu_id"],
            name=r["bu_name"],
            role=r["role"],
            is_primary=r["is_primary"],
            assigned_by_name=r["assigned_by_name"],
        )
        for r in roles
    ]

    # Touch last_active_at and ensure a live session for this device.
    conn.execute(
        "UPDATE app_user SET last_active_at = now(), updated_at = now() WHERE id = %s",
        (str(app_user_id),),
    )
    session = conn.execute(
        """
        SELECT id, active_bu_id FROM user_session
         WHERE user_id = %s AND device_id = %s AND revoked_at IS NULL
        """,
        (str(app_user_id), device_id),
    ).fetchone()

    active_bu_id = session["active_bu_id"] if session else None
    if not session:
        # Default active unit: last_bu_id or primary unit
        default_bu = user["last_bu_id"]
        if default_bu is None:
            primary = next((u for u in units if u.is_primary and u.bu_id), None)
            default_bu = primary.bu_id if primary else next((u.bu_id for u in units if u.bu_id), None)
        conn.execute(
            """
            INSERT INTO user_session (tenant_id, user_id, device_id, active_bu_id, last_seen_at)
            VALUES (%s, %s, %s, %s, now())
            """,
            (str(tenant_id), str(app_user_id), device_id, str(default_bu) if default_bu else None),
        )
        active_bu_id = default_bu
    else:
        conn.execute(
            "UPDATE user_session SET last_seen_at = now(), updated_at = now() WHERE id = %s",
            (str(session["id"]),),
        )

    return Me(
        user_id=user["id"],
        full_name=user["full_name"],
        email=user["email"],
        phone_number=user["phone_number"],
        status=user["status"],
        tenant_name=user["tenant_name"],
        units=units,
        active_bu_id=active_bu_id,
        last_bu_id=user["last_bu_id"],
    )


def set_active_unit(
    conn: Connection, *, app_user_id: UUID, tenant_id: UUID, device_id: str, bu_id: UUID
) -> Me:
    allowed = conn.execute(
        """
        SELECT 1 FROM user_unit_role
         WHERE user_id = %s AND bu_id = %s AND removed_at IS NULL
        """,
        (str(app_user_id), str(bu_id)),
    ).fetchone()
    # EA has bu_id null — they may still switch into a unit they manage via EA policies;
    # for MVP require an explicit unit role or EA.
    is_ea = conn.execute(
        """
        SELECT 1 FROM user_unit_role
         WHERE user_id = %s AND role = 'enterprise_admin' AND removed_at IS NULL
        """,
        (str(app_user_id),),
    ).fetchone()
    if not allowed and not is_ea:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"title": "Forbidden", "detail": "No role in that unit"},
        )

    conn.execute(
        """
        UPDATE user_session
           SET active_bu_id = %s, last_seen_at = now(), updated_at = now()
         WHERE user_id = %s AND device_id = %s AND revoked_at IS NULL
        """,
        (str(bu_id), str(app_user_id), device_id),
    )
    conn.execute(
        "UPDATE app_user SET last_bu_id = %s, updated_at = now() WHERE id = %s",
        (str(bu_id), str(app_user_id)),
    )
    return get_me(conn, app_user_id=app_user_id, tenant_id=tenant_id, device_id=device_id)


def sign_out(conn: Connection, *, app_user_id: UUID, device_id: str) -> None:
    conn.execute(
        """
        UPDATE user_session
           SET revoked_at = now(), updated_at = now()
         WHERE user_id = %s AND device_id = %s AND revoked_at IS NULL
        """,
        (str(app_user_id), device_id),
    )
