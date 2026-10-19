"""Contracts 1.16-1.19: who runs which unit, and the technicians of a unit."""

from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Request, Response

from app.auth.context import SignedIn
from app.core.paging import Cursor, Limit
from app.services import mail, staff
from app.services.business_units import BuAdmin

router = APIRouter(tags=["Staff"])


@router.put("/bu-admins/{user_id}/business-units", operation_id="setBuAdminUnits")
async def set_admin_units(
    user_id: UUID, body: staff.AdminUnits, session: SignedIn, request: Request
) -> BuAdmin:
    return await staff.set_admin_units(session, request.app.state.keycloak, user_id, body.bu_ids)


@router.post("/bu-admins/{user_id}/remove", operation_id="removeBuAdmin", status_code=204)
async def remove_admin(
    user_id: UUID,
    body: staff.AdminRemoval,
    session: SignedIn,
    request: Request,
    background: BackgroundTasks,
) -> Response:
    replacement = await staff.remove_admin(session, request.app.state.keycloak, user_id, body)
    if replacement:
        email, token = replacement
        background.add_task(
            mail.send_invite, request.app.state.settings, to=email, token=token, role="bu_admin"
        )
    return Response(status_code=204)


@router.get("/business-units/{bu_id}/technicians", operation_id="listTechnicians")
async def list_technicians(
    bu_id: UUID, session: SignedIn, cursor: Cursor = None, limit: Limit = 25
) -> staff.TechnicianPage:
    return await staff.technicians(session, bu_id, cursor=cursor, limit=limit)


@router.post(
    "/business-units/{bu_id}/technicians/{user_id}/remove",
    operation_id="removeTechnician",
    status_code=204,
)
async def remove_technician(
    bu_id: UUID, user_id: UUID, session: SignedIn, request: Request
) -> Response:
    await staff.remove_technician(session, request.app.state.keycloak, bu_id, user_id)
    return Response(status_code=204)
