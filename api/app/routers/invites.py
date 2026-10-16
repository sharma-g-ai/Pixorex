import logging
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response

from app.db_ctx import rls_connection
from app.deps import CurrentUser, get_current_user
from app.models.invites import (
    CreateInviteBody,
    InviteAcceptBody,
    InviteAcceptResult,
    InvitePreview,
    InvitePreviewBody,
    InviteRow,
)
from app.services import invites as invite_service
from app.services.mail import send_invite_email

log = logging.getLogger(__name__)
router = APIRouter(prefix="/invites", tags=["Invites"])


@router.post("/preview", response_model=InvitePreview)
def preview(body: InvitePreviewBody) -> InvitePreview:
    return invite_service.preview(body)


@router.post("/accept", response_model=InviteAcceptResult, status_code=201)
def accept(body: InviteAcceptBody) -> InviteAcceptResult:
    return invite_service.accept(body)


@router.post("", status_code=201)
def create_invite(
    body: CreateInviteBody,
    user: Annotated[CurrentUser, Depends(get_current_user)],
) -> dict:
    with rls_connection(user, require_admin=True) as conn:
        ids, expires, raw = invite_service.create_invites(
            conn, tenant_id=user.tenant_id, invited_by=user.app_user_id, body=body
        )
    try:
        send_invite_email(to=str(body.email), token=raw, role=body.role)
    except OSError:
        log.exception("Invite email failed; invite rows %s remain for resend", ids)
    return {"invite_ids": ids, "expires_at": expires}


@router.get("", response_model=list[InviteRow])
def list_invites(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    status: Annotated[str | None, Query()] = None,
    bu_id: Annotated[UUID | None, Query()] = None,
) -> list[InviteRow]:
    with rls_connection(user, require_admin=True) as conn:
        return invite_service.list_invites(conn, status_filter=status, bu_id=bu_id)


@router.post("/{invite_id}/resend")
def resend(
    invite_id: UUID,
    user: Annotated[CurrentUser, Depends(get_current_user)],
) -> dict[str, datetime]:
    with rls_connection(user, require_admin=True) as conn:
        expires = invite_service.resend(conn, invite_id=invite_id, tenant_id=user.tenant_id)
        return {"expires_at": expires}


@router.post("/{invite_id}/cancel", status_code=204)
def cancel(
    invite_id: UUID,
    user: Annotated[CurrentUser, Depends(get_current_user)],
) -> Response:
    with rls_connection(user, require_admin=True) as conn:
        invite_service.cancel(conn, invite_id=invite_id, tenant_id=user.tenant_id)
        return Response(status_code=204)
