"""Contracts 1.12, 1.13, 1.15: units and the BU Admins who run them."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Header, Request

from app.auth.context import SignedIn
from app.core.paging import Cursor, Limit
from app.services import business_units, mail

router = APIRouter(tags=["Business units"])


@router.get("/business-units", operation_id="listBusinessUnits")
async def list_units(
    session: SignedIn, no_bu_admin: bool = False, cursor: Cursor = None, limit: Limit = 25
) -> business_units.UnitPage:
    return await business_units.list_page(
        session, vacant_only=no_bu_admin, cursor=cursor, limit=limit
    )


@router.post("/business-units", operation_id="createBusinessUnit", status_code=201)
async def create_unit(
    body: business_units.NewUnit,
    session: SignedIn,
    request: Request,
    background: BackgroundTasks,
    idempotency_key: Annotated[UUID, Header()],
) -> business_units.BusinessUnit:
    # TODO (open point): Idempotency-Key is required but not stored yet (no table in the model).
    unit, mail_to = await business_units.create(session, body)
    if mail_to:
        email, token = mail_to
        background.add_task(
            mail.send_invite, request.app.state.settings, to=email, token=token, role="bu_admin"
        )
    return unit


@router.get("/bu-admins", operation_id="listBuAdmins")
async def list_bu_admins(
    session: SignedIn, cursor: Cursor = None, limit: Limit = 25
) -> business_units.BuAdminPage:
    return await business_units.admins_page(session, cursor=cursor, limit=limit)
