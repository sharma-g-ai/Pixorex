"""Invites (contracts 1.6-1.11). A link's token is never stored, only its SHA-256."""

import hashlib
import re
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any, Literal
from uuid import UUID

from psycopg.errors import UniqueViolation
from pydantic import BaseModel

from app.core.emails import WorkEmail

from app.auth.context import Session, scope_to_invite
from app.auth.keycloak_admin import CrossTenantUserError, KeycloakAdmin, KeycloakUser
from app.core.db import Conn
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.repositories import audit, invites, users

LIFETIME = timedelta(hours=24)
InviteRole = Literal["bu_admin", "field_technician"]
_E164 = re.compile(r"^\+[1-9][0-9]{1,14}$")
_ROLE_TEXT = {"bu_admin": "BU Admin", "field_technician": "technician"}


class UnitRef(BaseModel):
    bu_id: UUID
    name: str


class InvitePreview(BaseModel):
    role: InviteRole
    email: str
    units: list[UnitRef]
    invited_by_name: str
    expires_at: datetime


class Accepted(BaseModel):
    user_id: UUID
    next_step: Literal["verify_phone", "verify_email"]


class Created(BaseModel):
    invite_ids: list[UUID]
    expires_at: datetime


class Invite(BaseModel):
    invite_id: UUID
    email: str
    role: InviteRole
    units: list[UnitRef]
    invited_by_name: str
    created_at: datetime
    expires_at: datetime
    status: Literal["pending", "accepted", "expired", "cancelled"]


class InvitePage(BaseModel):
    items: list[Invite]
    page: PageInfo


class NewInvite(BaseModel):
    role: InviteRole
    email: WorkEmail
    bu_ids: list[UUID]


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _new_token() -> tuple[str, str]:
    token = secrets.token_urlsafe(32)
    return token, hash_token(token)


def _dead_link(rows: list[dict[str, Any]]) -> ProblemError | None:
    """Contract 1.6/1.7 409 types, or None while the link still works."""
    status = rows[0]["status"] if rows else "missing"
    if status == "accepted":
        return ProblemError(409, "invite-used", "This invite was already used.")
    if status == "cancelled":
        return ProblemError(409, "invite-cancelled", "This invite was cancelled.")
    if status != "pending" or rows[0]["expires_at"] <= datetime.now(UTC):
        return ProblemError(409, "invite-expired", "This invite has expired.")
    return None


async def _rows_for_link(conn: Conn, token: str, *, lock: bool) -> list[dict[str, Any]]:
    token_hash = hash_token(token)
    rows = (
        await invites.by_token(conn, token_hash, lock=lock)
        if await scope_to_invite(conn, token_hash)
        else []
    )
    problem = _dead_link(rows)
    if problem:
        raise problem
    return rows


async def preview(conn: Conn, token: str) -> InvitePreview:
    rows = await _rows_for_link(conn, token, lock=False)
    return InvitePreview(
        role=rows[0]["role"],
        email=rows[0]["email"],
        units=[UnitRef(bu_id=r["bu_id"], name=r["bu_name"]) for r in rows],
        invited_by_name=rows[0]["invited_by_name"],
        expires_at=rows[0]["expires_at"],
    )


async def accept(
    conn: Conn, keycloak: KeycloakAdmin, *, token: str, full_name: str, phone: str | None
) -> Accepted:
    rows = await _rows_for_link(conn, token, lock=True)
    first = rows[0]
    tenant_id, role, email = first["tenant_id"], first["role"], first["email"]
    if role == "field_technician":
        if not phone or not _E164.match(phone):
            raise ProblemError(
                400,
                "validation",
                "Some fields are not valid.",
                errors=[{"field": "phone_number", "message": "Enter the number as +15551234567."}],
            )
    else:
        phone = None  # admins sign in by email only

    # Accepting takes every other live invite of this person for this role (D-09);
    # the primary unit is the oldest invite's unit.
    all_rows = sorted(
        rows + await invites.other_pending(conn, email, role, first["token_hash"]),
        key=lambda r: r["created_at"],
    )
    user_id = await _upsert_person(conn, tenant_id, email, full_name, phone)
    await _grant_units(conn, user_id, all_rows)
    await invites.set_status(conn, [r["id"] for r in all_rows], "accepted")

    first_name, _, last_name = full_name.strip().partition(" ")
    try:
        kc_id = await keycloak.ensure_user(
            KeycloakUser(
                app_user_id=str(user_id),
                tenant_id=str(tenant_id),
                email=email,
                realm_role="pixorex-mobile" if role == "field_technician" else "pixorex-web",
                email_verified=role == "field_technician",  # technicians verify the phone
                phone_number=phone,
                first_name=first_name or None,
                last_name=last_name or None,
            )
        )
    except CrossTenantUserError:
        raise ProblemError(409, "email-in-use", "This email already signs in elsewhere.") from None
    await users.set_keycloak_id(conn, user_id, kc_id)
    return Accepted(
        user_id=user_id,
        next_step="verify_phone" if role == "field_technician" else "verify_email",
    )


async def _upsert_person(
    conn: Conn, tenant_id: UUID, email: str, full_name: str, phone: str | None
) -> UUID:
    try:
        existing = await users.by_email(conn, email)
        if existing:
            await users.reinvite(conn, existing["id"], full_name, phone)
            return UUID(str(existing["id"]))
        return await users.create_invited(
            conn, tenant_id=tenant_id, email=email, full_name=full_name, phone=phone
        )
    except UniqueViolation:
        raise ProblemError(409, "phone-in-use", "This phone number is already used.") from None


async def _grant_units(conn: Conn, user_id: UUID, rows: list[dict[str, Any]]) -> None:
    role = rows[0]["role"]
    if role == "bu_admin":
        taken = [
            r
            for r in await users.active_roles_in(conn, [x["bu_id"] for x in rows], "bu_admin")
            if r["user_id"] != user_id
        ]
        if taken:
            raise ProblemError(409, "unit-has-bu-admin", "A unit already has a BU Admin.")
    needs_primary = not await users.has_primary(conn, user_id)
    for i, row in enumerate(rows):
        try:
            await users.add_role(
                conn,
                tenant_id=row["tenant_id"],
                user_id=user_id,
                bu_id=row["bu_id"],
                role=role,
                is_primary=needs_primary and i == 0,
                assigned_by=row["invited_by"],
            )
        except UniqueViolation:  # someone else became BU Admin meanwhile
            raise ProblemError(409, "unit-has-bu-admin", "A unit already has a BU Admin.") from None
        await audit.record(
            conn,
            tenant_id=row["tenant_id"],
            actor_user_id=user_id,
            bu_id=row["bu_id"],
            category="users",
            action="invite.accepted",
            summary=f"Accepted the invite as {_ROLE_TEXT[role]}",
            object_type="invite",
            object_id=row["id"],
        )


async def create(session: Session, body: NewInvite) -> tuple[Created, str]:
    """Returns the result and the link token to email after the commit."""
    caller, conn = session.caller, session.conn
    bu_ids = list(dict.fromkeys(body.bu_ids))
    if not bu_ids:
        raise ProblemError(400, "validation", "Pick at least one unit.")
    if body.role == "bu_admin":
        caller.require_ea()  # EA invites BU Admins to units without one
        if await users.active_roles_in(conn, bu_ids, "bu_admin"):
            raise ProblemError(409, "unit-has-bu-admin", "A unit already has a BU Admin.")
    elif not set(bu_ids) <= caller.units("bu_admin"):
        raise ProblemError(403, "forbidden", "You can invite technicians to your own units only.")

    token, token_hash = _new_token()
    expires = datetime.now(UTC) + LIFETIME
    email = str(body.email).lower()
    ids = []
    for bu_id in bu_ids:
        ids.append(
            await invites.insert(
                conn,
                tenant_id=caller.tenant_id,
                bu_id=bu_id,
                email=email,
                role=body.role,
                token_hash=token_hash,
                invited_by=caller.user_id,
                expires_at=expires,
            )
        )
        await audit.record(
            conn,
            tenant_id=caller.tenant_id,
            actor_user_id=caller.user_id,
            bu_id=bu_id,
            category="users",
            action="invite.created",
            summary=f"Invited {email} as {_ROLE_TEXT[body.role]}",
            object_type="invite",
            object_id=ids[-1],
        )
    return Created(invite_ids=ids, expires_at=expires), token


async def list_page(
    session: Session, *, status: str | None, bu_id: UUID | None, cursor: str | None, limit: int
) -> InvitePage:
    caller = session.caller
    # Contract 1.9: the EA sees BU Admin invites; a BU Admin sees technician invites of their units.
    if caller.is_ea:
        role, units = "bu_admin", None
    else:
        caller.require_admin()
        role, units = "field_technician", sorted(caller.units("bu_admin"))
    rows = await invites.page(
        session.conn,
        role=role,
        units=units,
        status=status,
        bu_id=bu_id,
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return InvitePage(
        items=[Invite(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["created_at"].isoformat(), rows[-1]["invite_id"])
            if more
            else None
        ),
    )


async def _own_group(session: Session, invite_id: UUID) -> list[dict[str, Any]]:
    """The invite's rows, if the caller may manage it (same rule as the list)."""
    caller = session.caller
    rows = await invites.group_of(session.conn, invite_id)
    allowed = rows and (
        (caller.is_ea and rows[0]["role"] == "bu_admin")
        or (
            rows[0]["role"] == "field_technician"
            and {r["bu_id"] for r in rows} <= caller.units("bu_admin")
        )
    )
    if not allowed:
        raise ProblemError(404, "not-found")
    return rows


async def resend(session: Session, invite_id: UUID) -> tuple[datetime, str, str, str]:
    """New link and 24 hours; returns (expires_at, email, role, token) to email after commit."""
    rows = await _own_group(session, invite_id)
    if rows[0]["status"] in ("accepted", "cancelled"):
        raise ProblemError(409, "invalid-state", "This invite was already used or cancelled.")
    token, token_hash = _new_token()
    expires = datetime.now(UTC) + LIFETIME
    await invites.renew(session.conn, [r["id"] for r in rows], token_hash, expires)
    await _audit_each(session, rows, "invite.resent", f"Resent the invite to {rows[0]['email']}")
    return expires, rows[0]["email"], rows[0]["role"], token


async def cancel(session: Session, invite_id: UUID) -> None:
    rows = await _own_group(session, invite_id)
    if rows[0]["status"] == "accepted":
        raise ProblemError(409, "invalid-state", "This invite was already used.")
    if rows[0]["status"] == "cancelled":
        return  # already cancelled: same outcome
    await invites.set_status(session.conn, [r["id"] for r in rows], "cancelled")
    await _audit_each(
        session, rows, "invite.cancelled", f"Cancelled the invite to {rows[0]['email']}"
    )


async def _audit_each(
    session: Session, rows: list[dict[str, Any]], action: str, summary: str
) -> None:
    for row in rows:
        await audit.record(
            session.conn,
            tenant_id=session.caller.tenant_id,
            actor_user_id=session.caller.user_id,
            bu_id=row["bu_id"],
            category="users",
            action=action,
            summary=summary,
            object_type="invite",
            object_id=row["id"],
        )
