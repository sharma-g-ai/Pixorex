from __future__ import annotations

import logging
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query

from app.db_ctx import rls_connection
from app.deps import CurrentUser, get_current_user
from app.models.business_units import BusinessUnit, BusinessUnitList, CreateBusinessUnitBody
from app.services import business_units as bu_service
from app.services.mail import send_invite_email

log = logging.getLogger(__name__)
router = APIRouter(prefix="/business-units", tags=["Business units"])


@router.get("", response_model=BusinessUnitList)
def list_business_units(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    no_bu_admin: Annotated[bool | None, Query()] = None,
) -> BusinessUnitList:
    with rls_connection(user, require_admin=True) as conn:
        return bu_service.list_business_units(conn, no_bu_admin=no_bu_admin)


@router.post("", response_model=BusinessUnit, status_code=201)
def create_business_unit(
    body: CreateBusinessUnitBody,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    idempotency_key: Annotated[UUID | None, Header(alias="Idempotency-Key")] = None,
) -> BusinessUnit:
    _ = idempotency_key  # accepted per contract; durable store not required for local MVP
    with rls_connection(user, require_ea=True) as conn:
        unit, pending_mail = bu_service.create_business_unit(
            conn,
            tenant_id=user.tenant_id,
            invited_by=user.app_user_id,
            body=body,
        )
    # Unit is already committed; email failure must not hide the created unit.
    if pending_mail:
        email, token, role = pending_mail
        try:
            send_invite_email(to=email, token=token, role=role)
        except OSError:
            log.exception("Invite email failed for unit %s; invite row remains for resend", unit.bu_id)
    return unit
