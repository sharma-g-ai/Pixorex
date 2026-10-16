"""The signed-in person (contracts 1.1-1.3)."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.auth.context import Session
from app.core.problems import ProblemError
from app.repositories import audit, users

Role = Literal["enterprise_admin", "bu_admin", "field_technician"]


class UnitRole(BaseModel):
    bu_id: UUID | None
    name: str | None
    role: Role
    is_primary: bool
    assigned_by_name: str | None


class Me(BaseModel):
    user_id: UUID
    full_name: str
    email: str
    phone_number: str | None
    status: Literal["invited", "active", "removed"]
    tenant_name: str
    units: list[UnitRole]
    active_bu_id: UUID | None
    last_bu_id: UUID | None


async def get_me(session: Session) -> Me:
    caller, conn = session.caller, session.conn
    await users.mark_seen(conn, caller.user_id)
    profile = await users.profile(conn, caller.user_id)
    if profile is None:  # cannot happen after the context check; kept for the type
        raise ProblemError(401, "unauthorized")
    units = [UnitRole(**r) for r in await users.unit_roles(conn, caller.user_id)]

    live = await users.live_session(conn, caller.user_id, caller.device_id)
    if live is None:
        active = _default_unit(profile["last_bu_id"], units)
        await users.open_session(
            conn,
            tenant_id=caller.tenant_id,
            user_id=caller.user_id,
            device_id=caller.device_id,
            bu_id=active,
        )
    else:
        active = live["active_bu_id"]
        await users.touch_session(conn, live["id"])
    return Me(
        user_id=profile["id"],
        full_name=profile["full_name"],
        email=profile["email"],
        phone_number=profile["phone_number"],
        status=profile["status"],
        tenant_name=profile["tenant_name"],
        units=units,
        active_bu_id=active,
        last_bu_id=profile["last_bu_id"],
    )


def _default_unit(last_bu_id: UUID | None, units: list[UnitRole]) -> UUID | None:
    """Last unit used if still held, else the primary unit, else the first one."""
    held = [u.bu_id for u in units if u.bu_id]
    if last_bu_id in held:
        return last_bu_id
    primary = next((u.bu_id for u in units if u.is_primary and u.bu_id), None)
    return primary or (held[0] if held else None)


async def set_active_unit(session: Session, bu_id: UUID) -> Me:
    caller = session.caller
    if bu_id not in caller.bu_ids:  # contract 1.2: an active role in that unit
        raise ProblemError(403, "forbidden", "You have no role in that unit.")
    await users.set_active_unit(session.conn, caller.user_id, caller.device_id, bu_id)
    return await get_me(session)


async def sign_out(session: Session) -> None:
    caller = session.caller
    await users.revoke_session(session.conn, caller.user_id, caller.device_id)
    await audit.record(
        session.conn,
        tenant_id=caller.tenant_id,
        actor_user_id=caller.user_id,
        category="sign_in",
        action="session.signed_out",
        summary="Signed out",
        object_type="app_user",
        object_id=caller.user_id,
    )
