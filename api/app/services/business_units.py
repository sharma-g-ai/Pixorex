"""Business units and BU Admins (contracts 1.12, 1.13, 1.15)."""

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from psycopg.errors import UniqueViolation
from pydantic import BaseModel, Field

from app.core.emails import WorkEmail

from app.auth.context import Session
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.repositories import audit, business_units, users
from app.services import invites


class UserRef(BaseModel):
    user_id: UUID
    full_name: str


class BusinessUnit(BaseModel):
    bu_id: UUID
    name: str
    facility_name: str
    bu_admin: UserRef | None
    waiting_count: int  # scans waiting for approval
    escalated_count: int  # open escalations
    delegated_count: int  # scans in open delegated assignments
    technician_count: int
    scans_this_month: int
    vacant_since: datetime | None  # set only while the unit has no BU Admin
    previous_bu_admin: UserRef | None  # the BU Admin who left, while vacant
    locations_status: Literal["not_published", "published"]


class UnitPage(BaseModel):
    items: list[BusinessUnit]
    page: PageInfo


class InviteAdmin(BaseModel):
    invite_email: WorkEmail


class ExistingAdmin(BaseModel):
    user_id: UUID


class NewUnit(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    facility_name: str = Field(min_length=1, max_length=200)
    bu_admin: InviteAdmin | ExistingAdmin


class BuAdmin(BaseModel):
    user_id: UUID
    full_name: str
    email: str
    units: list[invites.UnitRef]
    status: Literal["invited", "active", "removed"]
    last_active_at: datetime | None


class BuAdminPage(BaseModel):
    items: list[BuAdmin]
    page: PageInfo


def _unit(row: dict[str, Any]) -> BusinessUnit:
    admin = None
    if row["admin_id"]:
        admin = UserRef(user_id=row["admin_id"], full_name=row["admin_name"])
    return BusinessUnit(
        bu_id=row["bu_id"],
        name=row["name"],
        facility_name=row["facility_name"],
        bu_admin=admin,
        locations_status=row["locations_status"],
        waiting_count=row["waiting_count"],
        escalated_count=row["escalated_count"],
        delegated_count=row["delegated_count"],
        technician_count=row["technician_count"],
        scans_this_month=row["scans_this_month"],
        vacant_since=row["vacant_since"],
        previous_bu_admin=(
            UserRef(user_id=row["prev_id"], full_name=row["prev_name"]) if row["prev_id"] else None
        ),
    )


async def list_page(
    session: Session, *, vacant_only: bool, cursor: str | None, limit: int
) -> UnitPage:
    caller = session.caller
    caller.require_admin()
    # RLS lets a person read every unit they hold any role in; a BU Admin's list is the units
    # they run (REQ-04.07), not the ones where they are also a technician.
    units = None if caller.is_ea else sorted(caller.units("bu_admin"))
    rows = await business_units.page(
        session.conn,
        units=units,
        vacant_only=vacant_only,
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = encode_cursor(rows[-1]["name"], rows[-1]["bu_id"]) if more else None
    return UnitPage(items=[_unit(r) for r in rows], page=PageInfo(next_cursor=next_cursor))


async def create(session: Session, body: NewUnit) -> tuple[BusinessUnit, tuple[str, str] | None]:
    """Returns the unit and, when a BU Admin was invited, (email, token) to send after commit."""
    caller, conn = session.caller, session.conn
    caller.require_ea()
    name, facility = body.name.strip(), body.facility_name.strip()
    if not name or not facility:
        raise ProblemError(400, "validation", "Enter the unit name and the facility.")
    existing_admin = body.bu_admin if isinstance(body.bu_admin, ExistingAdmin) else None
    if existing_admin and not await business_units.is_bu_admin(conn, existing_admin.user_id):
        raise ProblemError(409, "not-a-bu-admin", "This person is not a BU Admin.")
    try:
        bu_id = await business_units.create(
            conn, tenant_id=caller.tenant_id, name=name, facility=facility
        )
    except UniqueViolation:
        raise ProblemError(409, "duplicate-name", "A unit with this name already exists.") from None
    await audit.record(
        conn,
        tenant_id=caller.tenant_id,
        actor_user_id=caller.user_id,
        bu_id=bu_id,
        category="users",
        action="business_unit.created",
        summary=f"Created unit {name}",
        object_type="business_unit",
        object_id=bu_id,
    )

    mail_to: tuple[str, str] | None = None
    if existing_admin:
        await users.add_role(
            conn,
            tenant_id=caller.tenant_id,
            user_id=existing_admin.user_id,
            bu_id=bu_id,
            role="bu_admin",
            is_primary=False,
            assigned_by=caller.user_id,
        )
    elif isinstance(body.bu_admin, InviteAdmin):
        new = invites.NewInvite(role="bu_admin", email=body.bu_admin.invite_email, bu_ids=[bu_id])
        _, token = await invites.create(session, new)
        mail_to = (str(new.email), token)

    row = await business_units.one(conn, bu_id)
    if row is None:
        raise RuntimeError("the new unit is not visible to its creator")
    return _unit(row), mail_to


async def admins_page(session: Session, *, cursor: str | None, limit: int) -> BuAdminPage:
    session.caller.require_ea()
    rows = await business_units.admins_page(
        session.conn, after=decode_cursor(cursor, 2), limit=limit
    )
    more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = encode_cursor(rows[-1]["full_name"], rows[-1]["user_id"]) if more else None
    return BuAdminPage(items=[BuAdmin(**r) for r in rows], page=PageInfo(next_cursor=next_cursor))
