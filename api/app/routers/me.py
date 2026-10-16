"""Contracts 1.1-1.3: the signed-in person, unit switching, sign-out."""

from uuid import UUID

from fastapi import APIRouter, Response
from pydantic import BaseModel

from app.auth.context import SignedIn
from app.services import me

router = APIRouter(prefix="/me", tags=["Session"])


class ActiveUnit(BaseModel):
    bu_id: UUID


@router.get("", operation_id="getMe")
async def get_me(session: SignedIn) -> me.Me:
    return await me.get_me(session)


@router.put("/active-unit", operation_id="setActiveUnit")
async def set_active_unit(body: ActiveUnit, session: SignedIn) -> me.Me:
    return await me.set_active_unit(session, body.bu_id)


@router.post("/sign-out", operation_id="signOut", status_code=204)
async def sign_out(session: SignedIn) -> Response:
    await me.sign_out(session)
    return Response(status_code=204)
