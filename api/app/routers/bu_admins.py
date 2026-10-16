from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from app.db_ctx import rls_connection
from app.deps import CurrentUser, get_current_user
from app.models.business_units import BuAdminList
from app.services import business_units as bu_service

router = APIRouter(prefix="/bu-admins", tags=["BU Admins"])


@router.get("", response_model=BuAdminList)
def list_bu_admins(
    user: Annotated[CurrentUser, Depends(get_current_user)],
) -> BuAdminList:
    with rls_connection(user, require_ea=True) as conn:
        return bu_service.list_bu_admins(conn)
