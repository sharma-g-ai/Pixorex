from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from fastapi import HTTPException, status
from psycopg import Connection
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.auth.keycloak_admin import KeycloakAdmin
from app.config import get_settings
from app.models.invites import (
    CreateInviteBody,
    InviteAcceptBody,
    InviteAcceptResult,
    InvitePreview,
    InvitePreviewBody,
    InviteRow,
    UnitRef,
)
from app.services.mail import send_invite_email

_owner_pool: ConnectionPool | None = None


def _owner() -> ConnectionPool:
    global _owner_pool
    if _owner_pool is None:
        _owner_pool = ConnectionPool(
            conninfo=get_settings().database_owner_url,
            min_size=1,
            max_size=5,
            kwargs={"row_factory": dict_row},
            open=True,
        )
    return _owner_pool


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _problem(status_code: int, code: str, title: str) -> HTTPException:
    return HTTPException(status_code=status_code, detail={"title": title, "type": code, "code": code})


def preview(body: InvitePreviewBody) -> InvitePreview:
    token_hash = _hash_token(body.token)
    with _owner().connection() as conn:
        rows = conn.execute(
            """
            SELECT i.role, i.email, i.status, i.expires_at, i.bu_id, bu.name AS bu_name,
                   inv.full_name AS invited_by_name
              FROM invite i
              JOIN business_unit bu ON bu.id = i.bu_id AND bu.tenant_id = i.tenant_id
              JOIN app_user inv ON inv.id = i.invited_by AND inv.tenant_id = i.tenant_id
             WHERE i.token_hash = %s
            """,
            (token_hash,),
        ).fetchall()
        if not rows:
            raise _problem(409, "invite-expired", "Invite not found or no longer valid")
        row = rows[0]
        now = datetime.now(timezone.utc)
        if row["status"] == "accepted":
            raise _problem(409, "invite-used", "This invite was already used")
        if row["status"] == "cancelled":
            raise _problem(409, "invite-cancelled", "This invite was cancelled")
        if row["status"] != "pending" or row["expires_at"] < now:
            raise _problem(409, "invite-expired", "This invite has expired")
        return InvitePreview(
            role=row["role"],
            email=row["email"],
            units=[UnitRef(bu_id=r["bu_id"], name=r["bu_name"]) for r in rows],
            invited_by_name=row["invited_by_name"],
            expires_at=row["expires_at"],
        )


def accept(body: InviteAcceptBody) -> InviteAcceptResult:
    token_hash = _hash_token(body.token)
    settings = get_settings()
    with _owner().connection() as conn:
        with conn.transaction():
            rows = conn.execute(
                """
                SELECT i.* FROM invite i WHERE i.token_hash = %s FOR UPDATE
                """,
                (token_hash,),
            ).fetchall()
            if not rows:
                raise _problem(409, "invite-expired", "Invite not found or no longer valid")
            row = rows[0]
            now = datetime.now(timezone.utc)
            if row["status"] == "accepted":
                raise _problem(409, "invite-used", "This invite was already used")
            if row["status"] == "cancelled":
                raise _problem(409, "invite-cancelled", "This invite was cancelled")
            if row["status"] != "pending" or row["expires_at"] < now:
                raise _problem(409, "invite-expired", "This invite has expired")

            role = row["role"]
            if role == "field_technician":
                if not body.phone_number:
                    raise HTTPException(
                        status_code=400,
                        detail={"title": "Bad Request", "detail": "phone_number is required"},
                    )
            else:
                body.phone_number = None

            existing = conn.execute(
                """
                SELECT id, keycloak_user_id, status FROM app_user
                 WHERE tenant_id = %s AND lower(email) = lower(%s)
                """,
                (str(row["tenant_id"]), row["email"]),
            ).fetchone()

            if existing:
                user_id = existing["id"]
                conn.execute(
                    """
                    UPDATE app_user
                       SET full_name = %s,
                           phone_number = COALESCE(%s, phone_number),
                           status = CASE WHEN status = 'removed' THEN 'invited' ELSE status END,
                           updated_at = now()
                     WHERE id = %s
                    """,
                    (body.full_name, body.phone_number, str(user_id)),
                )
            else:
                user_id = uuid4()
                conn.execute(
                    """
                    INSERT INTO app_user (id, tenant_id, email, full_name, phone_number, status)
                    VALUES (%s, %s, %s, %s, %s, 'invited')
                    """,
                    (
                        str(user_id),
                        str(row["tenant_id"]),
                        row["email"],
                        body.full_name,
                        body.phone_number,
                    ),
                )

            for inv in rows:
                # Contract 1.8 / 1.17: EA may invite a BU Admin only when the unit has none.
                # Replacing an existing admin is an explicit remove (+ optional replacement invite).
                if role == "bu_admin":
                    other = conn.execute(
                        """
                        SELECT user_id FROM user_unit_role
                         WHERE bu_id = %s AND role = 'bu_admin' AND removed_at IS NULL
                           AND user_id <> %s
                         LIMIT 1
                        """,
                        (str(inv["bu_id"]), str(user_id)),
                    ).fetchone()
                    if other:
                        raise _problem(
                            409,
                            "unit-has-bu-admin",
                            "This unit already has a BU Admin. Remove them first, then invite a replacement.",
                        )

                # Add role if missing
                has = conn.execute(
                    """
                    SELECT id FROM user_unit_role
                     WHERE user_id = %s AND bu_id IS NOT DISTINCT FROM %s
                       AND role = %s AND removed_at IS NULL
                    """,
                    (str(user_id), str(inv["bu_id"]), role),
                ).fetchone()
                if not has:
                    primary = conn.execute(
                        "SELECT 1 FROM user_unit_role WHERE user_id = %s AND is_primary AND removed_at IS NULL",
                        (str(user_id),),
                    ).fetchone()
                    try:
                        conn.execute(
                            """
                            INSERT INTO user_unit_role
                              (tenant_id, user_id, bu_id, role, is_primary, assigned_by)
                            VALUES (%s, %s, %s, %s, %s, %s)
                            """,
                            (
                                str(inv["tenant_id"]),
                                str(user_id),
                                str(inv["bu_id"]),
                                role,
                                primary is None,
                                str(inv["invited_by"]),
                            ),
                        )
                    except UniqueViolation:
                        raise _problem(
                            409,
                            "unit-has-bu-admin",
                            "This unit already has a BU Admin",
                        ) from None

                if role == "bu_admin":
                    conn.execute(
                        """
                        UPDATE business_unit
                           SET bu_admin_user_id = %s, updated_at = now()
                         WHERE id = %s AND tenant_id = %s
                        """,
                        (str(user_id), str(inv["bu_id"]), str(inv["tenant_id"])),
                    )

                conn.execute(
                    """
                    UPDATE invite SET status = 'accepted', accepted_at = now(), updated_at = now()
                     WHERE id = %s
                    """,
                    (str(inv["id"]),),
                )

            kc_role = "pixorex-mobile" if role == "field_technician" else "pixorex-web"
            parts = body.full_name.strip().split(None, 1)
            first = parts[0] if parts else None
            last = parts[1] if len(parts) > 1 else None
            admin = KeycloakAdmin(settings)
            kc_id = admin.ensure_user(
                app_user_id=str(user_id),
                email=row["email"],
                tenant_id=str(row["tenant_id"]),
                realm_roles=[kc_role],
                enabled=True,
                email_verified=False if role != "field_technician" else True,
                phone_number=body.phone_number,
                phone_verified=False,
                first_name=first,
                last_name=last,
            )
            conn.execute(
                "UPDATE app_user SET keycloak_user_id = %s, updated_at = now() WHERE id = %s",
                (kc_id, str(user_id)),
            )

            next_step = "verify_phone" if role == "field_technician" else "verify_email"
            return InviteAcceptResult(user_id=user_id, next_step=next_step)


def create_invites(
    conn: Connection,
    *,
    tenant_id: UUID,
    invited_by: UUID,
    body: CreateInviteBody,
) -> tuple[list[UUID], datetime, str]:
    """Insert invite rows. Returns (invite_ids, expires_at, raw_token).
    Caller must send the email after the DB transaction commits."""
    if body.role not in ("bu_admin", "field_technician"):
        raise HTTPException(status_code=400, detail={"title": "Bad Request", "detail": "Invalid role"})

    raw = secrets.token_urlsafe(32)
    token_hash = _hash_token(raw)
    expires = datetime.now(timezone.utc) + timedelta(hours=24)
    ids: list[UUID] = []

    for bu_id in body.bu_ids:
        bu = conn.execute(
            "SELECT id FROM business_unit WHERE id = %s AND tenant_id = %s",
            (str(bu_id), str(tenant_id)),
        ).fetchone()
        if not bu:
            raise HTTPException(status_code=403, detail={"title": "Forbidden", "detail": "Unknown unit"})
        invite_id = uuid4()
        conn.execute(
            """
            INSERT INTO invite
              (id, tenant_id, bu_id, email, role, token_hash, invited_by, status, expires_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'pending', %s)
            """,
            (
                str(invite_id),
                str(tenant_id),
                str(bu_id),
                str(body.email).lower(),
                body.role,
                token_hash,
                str(invited_by),
                expires,
            ),
        )
        ids.append(invite_id)

    # Ensure Keycloak placeholder user exists so first sign-in can resolve the email
    # (accept will upsert again with full_name).
    existing = conn.execute(
        "SELECT id FROM app_user WHERE tenant_id = %s AND lower(email) = lower(%s)",
        (str(tenant_id), str(body.email)),
    ).fetchone()
    app_user_id = existing["id"] if existing else uuid4()
    if not existing:
        conn.execute(
            """
            INSERT INTO app_user (id, tenant_id, email, full_name, status)
            VALUES (%s, %s, %s, %s, 'invited')
            """,
            (str(app_user_id), str(tenant_id), str(body.email).lower(), str(body.email)),
        )

    kc_role = "pixorex-mobile" if body.role == "field_technician" else "pixorex-web"
    try:
        kc_id = KeycloakAdmin().ensure_user(
            app_user_id=str(app_user_id),
            email=str(body.email).lower(),
            tenant_id=str(tenant_id),
            realm_roles=[kc_role],
            enabled=True,
            email_verified=False,
        )
        conn.execute(
            "UPDATE app_user SET keycloak_user_id = %s, updated_at = now() WHERE id = %s",
            (kc_id, str(app_user_id)),
        )
    except Exception:
        # Invite rows still useful; Keycloak can be fixed on accept
        pass

    return ids, expires, raw


def list_invites(conn: Connection, *, status_filter: str | None, bu_id: UUID | None) -> list[InviteRow]:
    clauses = ["1=1"]
    params: list[object] = []
    if status_filter:
        clauses.append("i.status = %s")
        params.append(status_filter)
    if bu_id:
        clauses.append("i.bu_id = %s")
        params.append(str(bu_id))
    where = " AND ".join(clauses)
    rows = conn.execute(
        f"""
        SELECT i.id AS invite_id, i.email, i.role, i.status, i.created_at, i.expires_at,
               i.token_hash, i.bu_id, bu.name AS bu_name, inv.full_name AS invited_by_name
          FROM invite i
          JOIN business_unit bu ON bu.id = i.bu_id AND bu.tenant_id = i.tenant_id
          JOIN app_user inv ON inv.id = i.invited_by AND inv.tenant_id = i.tenant_id
         WHERE {where}
         ORDER BY i.created_at DESC
        """,
        params,
    ).fetchall()

    # Group by token_hash for multi-unit invites
    grouped: dict[str, InviteRow] = {}
    for r in rows:
        key = r["token_hash"]
        unit = UnitRef(bu_id=r["bu_id"], name=r["bu_name"])
        if key not in grouped:
            status_val = r["status"]
            if status_val == "pending" and r["expires_at"] < datetime.now(timezone.utc):
                status_val = "expired"
            grouped[key] = InviteRow(
                invite_id=r["invite_id"],
                email=r["email"],
                role=r["role"],
                units=[unit],
                invited_by_name=r["invited_by_name"],
                created_at=r["created_at"],
                expires_at=r["expires_at"],
                status=status_val,
            )
        else:
            grouped[key].units.append(unit)
    return list(grouped.values())


def resend(conn: Connection, *, invite_id: UUID, tenant_id: UUID) -> datetime:
    row = conn.execute(
        "SELECT * FROM invite WHERE id = %s AND tenant_id = %s",
        (str(invite_id), str(tenant_id)),
    ).fetchone()
    if not row or row["status"] not in ("pending", "expired"):
        raise HTTPException(status_code=404, detail={"title": "Not Found"})
    raw = secrets.token_urlsafe(32)
    token_hash = _hash_token(raw)
    expires = datetime.now(timezone.utc) + timedelta(hours=24)
    conn.execute(
        """
        UPDATE invite
           SET token_hash = %s, status = 'pending', expires_at = %s, updated_at = now()
         WHERE token_hash = %s AND tenant_id = %s
        """,
        (token_hash, expires, row["token_hash"], str(tenant_id)),
    )
    send_invite_email(to=row["email"], token=raw, role=row["role"])
    return expires


def cancel(conn: Connection, *, invite_id: UUID, tenant_id: UUID) -> None:
    row = conn.execute(
        "SELECT token_hash FROM invite WHERE id = %s AND tenant_id = %s",
        (str(invite_id), str(tenant_id)),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail={"title": "Not Found"})
    conn.execute(
        """
        UPDATE invite SET status = 'cancelled', updated_at = now()
         WHERE token_hash = %s AND tenant_id = %s AND status = 'pending'
        """,
        (row["token_hash"], str(tenant_id)),
    )
