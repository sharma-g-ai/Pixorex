"""Contracts 1.6-1.11: invite links, sending, listing, resending, cancelling."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Header, Request, Response
from pydantic import BaseModel, Field

from app.auth.context import Public, SignedIn
from app.core.paging import Cursor, Limit
from app.services import idempotency, invites, mail

router = APIRouter(prefix="/invites", tags=["Invites"])


class LinkToken(BaseModel):
    token: str = Field(min_length=16, max_length=200)


class Acceptance(LinkToken):
    full_name: str = Field(min_length=1, max_length=200)
    phone_number: str | None = None


class ResendResult(BaseModel):
    expires_at: datetime


@router.post("/preview", operation_id="previewInvite")
async def preview(body: LinkToken, conn: Public) -> invites.InvitePreview:
    return await invites.preview(conn, body.token)


@router.post("/accept", operation_id="acceptInvite", status_code=201)
async def accept(body: Acceptance, conn: Public, request: Request) -> invites.Accepted:
    return await invites.accept(
        conn,
        request.app.state.keycloak,
        token=body.token,
        full_name=body.full_name.strip(),
        phone=body.phone_number,
    )


@router.post("", operation_id="createInvite", status_code=201, response_model=invites.Created)
async def create(
    body: invites.NewInvite,
    session: SignedIn,
    request: Request,
    background: BackgroundTasks,
    idempotency_key: Annotated[UUID, Header()],
) -> Response:
    async def run() -> Response:
        result, token = await invites.create(session, body)
        background.add_task(  # sent once: a repeated request returns the stored answer
            mail.send_invite,
            request.app.state.settings,
            to=str(body.email),
            token=token,
            role=body.role,
        )
        return idempotency.json_response(result, 201)

    return await idempotency.once(session, request, idempotency_key, run)


@router.get("", operation_id="listInvites")
async def list_invites(
    session: SignedIn,
    status: Literal["pending", "accepted", "expired", "cancelled"] | None = None,
    bu_id: UUID | None = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> invites.InvitePage:
    return await invites.list_page(session, status=status, bu_id=bu_id, cursor=cursor, limit=limit)


@router.post("/{invite_id}/resend", operation_id="resendInvite")
async def resend(
    invite_id: UUID, session: SignedIn, request: Request, background: BackgroundTasks
) -> ResendResult:
    expires, email, role, token = await invites.resend(session, invite_id)
    background.add_task(
        mail.send_invite, request.app.state.settings, to=email, token=token, role=role
    )
    return ResendResult(expires_at=expires)


@router.post("/{invite_id}/cancel", operation_id="cancelInvite", status_code=204)
async def cancel(invite_id: UUID, session: SignedIn) -> Response:
    await invites.cancel(session, invite_id)
    return Response(status_code=204)
