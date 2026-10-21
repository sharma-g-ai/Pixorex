"""BU Admin units and removal (contracts 1.16, 1.17); technicians (1.18, 1.19)."""

from datetime import datetime
from typing import Literal
from uuid import UUID

import httpx
from psycopg.errors import UniqueViolation
from pydantic import BaseModel

from app.auth.context import Session
from app.auth.keycloak_admin import KeycloakAdmin
from app.core.emails import WorkEmail
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.repositories import audit, business_units, invites, staff, users
from app.services import invites as invite_service
from app.services.business_units import BuAdmin
from app.services.invites import UnitRef

_ROLE_TEXT = {"bu_admin": "BU Admin", "field_technician": "technician"}


class AdminUnits(BaseModel):
    bu_ids: list[UUID]


class AdminRemoval(BaseModel):
    bu_ids: list[UUID]
    replacement_invite_email: WorkEmail | None = None


class Technician(BaseModel):
    user_id: UUID
    full_name: str
    email: str
    status: Literal["invited", "active", "removed"]
    # OPEN O-13: the lock lives in Keycloak; not exposed until that is decided.
    sign_in_locked_until: datetime | None
    units: list[UnitRef]
    scans_this_month: int
    active_batch_no: str | None
    last_active_at: datetime | None


class TechnicianPage(BaseModel):
    items: list[Technician]
    page: PageInfo


async def _admin(session: Session, user_id: UUID) -> BuAdmin:
    rows = await business_units.admins_page(session.conn, after=None, limit=1, user_id=user_id)
    if not rows:
        raise ProblemError(404, "not-found")
    return BuAdmin(**rows[0])


async def _disable_login(session: Session, keycloak: KeycloakAdmin, user_id: UUID) -> None:
    """Keycloak half of full removal (docs/keycloak.md §6.11). Fail closed if IdP is reachable
    but disable fails — otherwise login would keep working after we report success."""
    try:
        await keycloak.disable_login(
            app_user_id=str(user_id),
            keycloak_user_id=await users.keycloak_id(session.conn, user_id),
        )
    except (httpx.HTTPError, RuntimeError) as exc:
        raise ProblemError(
            502,
            "keycloak-unavailable",
            "Sign-in could not be disabled. Try again in a moment.",
        ) from exc


async def _detach(
    session: Session, user_id: UUID, bu_ids: list[UUID], role: str, keycloak: KeycloakAdmin
) -> None:
    """Shared removal rules: roles end (history kept), sessions in those units are revoked,
    open review assignments return to the queue, and with no role left the account is
    removed, every session revoked, and Keycloak login disabled (contracts 1.17, 1.19)."""
    caller, conn = session.caller, session.conn
    removed = await users.remove_roles(conn, user_id, bu_ids, role)
    for bu_id in removed:
        await users.revoke_sessions(conn, user_id, bu_id)
        await staff.release_assignments(conn, user_id=user_id, bu_id=bu_id, reason="user_removed")
        await audit.record(
            conn,
            tenant_id=caller.tenant_id,
            actor_user_id=caller.user_id,
            bu_id=bu_id,
            category="users",
            action="user.removed_from_unit",
            summary=f"Removed a {_ROLE_TEXT[role]} from the unit",
            object_type="app_user",
            object_id=user_id,
        )
    if await users.active_role_count(conn, user_id) == 0:
        await users.mark_removed(conn, user_id)
        await users.revoke_sessions(conn, user_id)
        await _disable_login(session, keycloak, user_id)
    else:
        await users.ensure_primary(conn, user_id)


async def set_admin_units(
    session: Session, keycloak: KeycloakAdmin, user_id: UUID, bu_ids: list[UUID]
) -> BuAdmin:
    """Contract 1.16: the full list of units this BU Admin runs."""
    caller, conn = session.caller, session.conn
    caller.require_ea()
    wanted = list(dict.fromkeys(bu_ids))
    if not wanted:
        raise ProblemError(400, "validation", "Keep at least one unit, or use Remove.")
    current = await users.units_with_role(conn, user_id, "bu_admin")
    if not current:
        raise ProblemError(404, "not-found")
    added = [b for b in wanted if b not in current]
    dropped = [b for b in current if b not in wanted]

    if added:
        if await users.active_roles_in(conn, added, "bu_admin"):
            raise ProblemError(409, "unit-has-bu-admin", "A unit is run by another BU Admin.")
        if await users.other_roles_in(conn, user_id, added, "bu_admin"):
            raise ProblemError(400, "validation", "This person has another role in that unit.")
        if not await business_units.all_visible(conn, added):
            raise ProblemError(404, "not-found")
        await invites.cancel_pending_for_units(conn, added, "bu_admin")
        for bu_id in added:
            try:
                await users.add_role(
                    conn,
                    tenant_id=caller.tenant_id,
                    user_id=user_id,
                    bu_id=bu_id,
                    role="bu_admin",
                    is_primary=False,
                    assigned_by=caller.user_id,
                )
            except UniqueViolation:  # another BU Admin took it meanwhile
                raise ProblemError(
                    409, "unit-has-bu-admin", "A unit is run by another BU Admin."
                ) from None
            await audit.record(
                conn,
                tenant_id=caller.tenant_id,
                actor_user_id=caller.user_id,
                bu_id=bu_id,
                category="users",
                action="bu_admin.assigned",
                summary="Assigned a BU Admin to the unit",
                object_type="app_user",
                object_id=user_id,
            )
    if dropped:
        await _detach(session, user_id, dropped, "bu_admin", keycloak)
    return await _admin(session, user_id)


async def remove_admin(
    session: Session, keycloak: KeycloakAdmin, user_id: UUID, body: AdminRemoval
) -> tuple[str, str] | None:
    """Contract 1.17. Returns (email, token) of the replacement invite to send after commit."""
    caller, conn = session.caller, session.conn
    caller.require_ea()
    bu_ids = list(dict.fromkeys(body.bu_ids))
    if not bu_ids:
        raise ProblemError(400, "validation", "Pick at least one unit.")
    current = await users.units_with_role(conn, user_id, "bu_admin")
    if not current:
        raise ProblemError(404, "not-found")
    if not set(bu_ids) <= current:
        raise ProblemError(400, "validation", "They don't run one of those units.")
    await _detach(session, user_id, bu_ids, "bu_admin", keycloak)
    if body.replacement_invite_email is None:
        return None
    new = invite_service.NewInvite(
        role="bu_admin", email=body.replacement_invite_email, bu_ids=bu_ids
    )
    _, token = await invite_service.create(session, new)
    return str(new.email), token


async def technicians(
    session: Session, bu_id: UUID, *, cursor: str | None, limit: int
) -> TechnicianPage:
    session.caller.require_bu_admin_of(bu_id)
    rows = await staff.technicians_page(
        session.conn, bu_id=bu_id, after=decode_cursor(cursor, 2), limit=limit
    )
    more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = encode_cursor(rows[-1]["full_name"], rows[-1]["user_id"]) if more else None
    return TechnicianPage(
        items=[
            Technician(**{**r, "units": r["units"] or [], "sign_in_locked_until": None})
            for r in rows
        ],
        page=PageInfo(next_cursor=next_cursor),
    )


async def remove_technician(
    session: Session, keycloak: KeycloakAdmin, bu_id: UUID, user_id: UUID
) -> None:
    """Contract 1.19: out of this unit only; their other units stay."""
    session.caller.require_bu_admin_of(bu_id)
    if bu_id not in await users.units_with_role(session.conn, user_id, "field_technician"):
        raise ProblemError(404, "not-found")
    await _detach(session, user_id, [bu_id], "field_technician", keycloak)
