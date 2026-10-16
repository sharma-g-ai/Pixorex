from __future__ import annotations

from uuid import UUID, uuid4

from fastapi import HTTPException
from psycopg import Connection
from psycopg.errors import UniqueViolation

from app.models.business_units import (
    BuAdmin,
    BuAdminList,
    BuAdminUnitRef,
    BusinessUnit,
    BusinessUnitList,
    CreateBusinessUnitBody,
    PageInfo,
    UserRef,
)
from app.models.invites import CreateInviteBody
from app.services.invites import create_invites


def _problem(status_code: int, code: str, title: str) -> HTTPException:
    return HTTPException(
        status_code=status_code,
        detail={"title": title, "type": f"/problems/{code}", "code": code, "status": status_code},
    )


def _row_to_unit(row: dict) -> BusinessUnit:
    admin = None
    if row.get("admin_user_id"):
        admin = UserRef(user_id=row["admin_user_id"], full_name=row["admin_full_name"])
    return BusinessUnit(
        bu_id=row["bu_id"],
        name=row["name"],
        facility_name=row["facility_name"],
        bu_admin=admin,
        waiting_count=int(row.get("waiting_count") or 0),
        escalated_count=int(row.get("escalated_count") or 0),
        delegated_count=int(row.get("delegated_count") or 0),
        locations_status=row.get("locations_status") or "not_published",
    )


def list_business_units(
    conn: Connection,
    *,
    no_bu_admin: bool | None = None,
) -> BusinessUnitList:
    clauses = ["1=1"]
    params: list[object] = []
    if no_bu_admin is True:
        clauses.append("bu.bu_admin_user_id IS NULL")
    where = " AND ".join(clauses)
    rows = conn.execute(
        f"""
        SELECT bu.id AS bu_id, bu.name, bu.facility_name,
               bu.bu_admin_user_id AS admin_user_id,
               admin.full_name AS admin_full_name,
               coalesce(lhv.status, 'not_published') AS locations_status
          FROM business_unit bu
          LEFT JOIN app_user admin
            ON admin.id = bu.bu_admin_user_id AND admin.tenant_id = bu.tenant_id
          LEFT JOIN location_hierarchy_version lhv
            ON lhv.bu_id = bu.id AND lhv.tenant_id = bu.tenant_id
         WHERE {where}
         ORDER BY bu.name
        """,
        params,
    ).fetchall()
    return BusinessUnitList(items=[_row_to_unit(r) for r in rows], page=PageInfo())


def create_business_unit(
    conn: Connection,
    *,
    tenant_id: UUID,
    invited_by: UUID,
    body: CreateBusinessUnitBody,
) -> tuple[BusinessUnit, tuple[str, str, str] | None]:
    """Returns (unit, optional (email, raw_token, role) to mail after commit)."""
    name = body.name.strip()
    facility = body.facility_name.strip()
    if not name or not facility:
        raise HTTPException(
            status_code=400,
            detail={"title": "Bad Request", "detail": "name and facility_name are required"},
        )

    bu_id = uuid4()
    admin_user_id: UUID | None = None

    if body.existing_user_id is not None:
        admin_user_id = body.existing_user_id
        admin = conn.execute(
            """
            SELECT u.id, u.full_name
              FROM app_user u
              JOIN user_unit_role uur
                ON uur.user_id = u.id AND uur.tenant_id = u.tenant_id
             WHERE u.id = %s AND u.tenant_id = %s
               AND uur.role = 'bu_admin' AND uur.removed_at IS NULL
             LIMIT 1
            """,
            (str(admin_user_id), str(tenant_id)),
        ).fetchone()
        if not admin:
            raise _problem(409, "not-a-bu-admin", "This person is not a BU Admin")

    try:
        conn.execute(
            """
            INSERT INTO business_unit
              (id, tenant_id, name, facility_name, bu_admin_user_id, status)
            VALUES (%s, %s, %s, %s, %s, 'active')
            """,
            (
                str(bu_id),
                str(tenant_id),
                name,
                facility,
                str(admin_user_id) if admin_user_id else None,
            ),
        )
    except UniqueViolation:
        raise _problem(409, "duplicate-name", "A unit with this name already exists") from None

    conn.execute(
        """
        INSERT INTO business_process (tenant_id, bu_id, name, is_default)
        VALUES (%s, %s, 'Default', true)
        """,
        (str(tenant_id), str(bu_id)),
    )
    conn.execute(
        """
        INSERT INTO location_hierarchy_version (tenant_id, bu_id, status)
        VALUES (%s, %s, 'not_published')
        """,
        (str(tenant_id), str(bu_id)),
    )

    pending_mail: tuple[str, str, str] | None = None
    if admin_user_id is not None:
        has = conn.execute(
            """
            SELECT id FROM user_unit_role
             WHERE user_id = %s AND bu_id = %s AND role = 'bu_admin' AND removed_at IS NULL
            """,
            (str(admin_user_id), str(bu_id)),
        ).fetchone()
        if not has:
            primary = conn.execute(
                "SELECT 1 FROM user_unit_role WHERE user_id = %s AND is_primary AND removed_at IS NULL",
                (str(admin_user_id),),
            ).fetchone()
            conn.execute(
                """
                INSERT INTO user_unit_role
                  (tenant_id, user_id, bu_id, role, is_primary, assigned_by)
                VALUES (%s, %s, %s, 'bu_admin', %s, %s)
                """,
                (
                    str(tenant_id),
                    str(admin_user_id),
                    str(bu_id),
                    primary is None,
                    str(invited_by),
                ),
            )
    elif body.invite_email:
        _ids, _expires, raw = create_invites(
            conn,
            tenant_id=tenant_id,
            invited_by=invited_by,
            body=CreateInviteBody(role="bu_admin", email=body.invite_email, bu_ids=[bu_id]),
        )
        pending_mail = (body.invite_email, raw, "bu_admin")

    row = conn.execute(
        """
        SELECT bu.id AS bu_id, bu.name, bu.facility_name,
               bu.bu_admin_user_id AS admin_user_id,
               admin.full_name AS admin_full_name,
               coalesce(lhv.status, 'not_published') AS locations_status
          FROM business_unit bu
          LEFT JOIN app_user admin
            ON admin.id = bu.bu_admin_user_id AND admin.tenant_id = bu.tenant_id
          LEFT JOIN location_hierarchy_version lhv
            ON lhv.bu_id = bu.id AND lhv.tenant_id = bu.tenant_id
         WHERE bu.id = %s
        """,
        (str(bu_id),),
    ).fetchone()
    assert row is not None
    return _row_to_unit(row), pending_mail


def list_bu_admins(conn: Connection) -> BuAdminList:
    rows = conn.execute(
        """
        SELECT u.id AS user_id, u.full_name, u.email, u.status, u.last_active_at,
               bu.id AS bu_id, bu.name AS bu_name
          FROM app_user u
          JOIN user_unit_role uur
            ON uur.user_id = u.id AND uur.tenant_id = u.tenant_id
           AND uur.role = 'bu_admin' AND uur.removed_at IS NULL
          LEFT JOIN business_unit bu
            ON bu.id = uur.bu_id AND bu.tenant_id = uur.tenant_id
         ORDER BY u.full_name, bu.name
        """
    ).fetchall()

    by_user: dict[UUID, BuAdmin] = {}
    for r in rows:
        uid = r["user_id"]
        if uid not in by_user:
            by_user[uid] = BuAdmin(
                user_id=uid,
                full_name=r["full_name"],
                email=r["email"],
                units=[],
                status=r["status"],
                last_active_at=r["last_active_at"],
            )
        if r["bu_id"]:
            by_user[uid].units.append(BuAdminUnitRef(bu_id=r["bu_id"], name=r["bu_name"]))
    return BuAdminList(items=list(by_user.values()), page=PageInfo())
