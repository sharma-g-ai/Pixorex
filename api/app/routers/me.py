from typing import Annotated

from fastapi import APIRouter, Depends, Response

from app.db_ctx import rls_connection
from app.deps import CurrentUser, get_current_user, get_device_id
from app.models.me import ActiveUnitBody, Me
from app.services import me as me_service

router = APIRouter(prefix="/me", tags=["Session"])


@router.get("", response_model=Me)
def get_me(user: Annotated[CurrentUser, Depends(get_current_user)]) -> Me:
    with rls_connection(user) as conn:
        return me_service.get_me(
            conn,
            app_user_id=user.app_user_id,
            tenant_id=user.tenant_id,
            device_id=user.device_id,
        )


@router.put("/active-unit", response_model=Me)
def active_unit(
    body: ActiveUnitBody,
    user: Annotated[CurrentUser, Depends(get_current_user)],
) -> Me:
    with rls_connection(user) as conn:
        return me_service.set_active_unit(
            conn,
            app_user_id=user.app_user_id,
            tenant_id=user.tenant_id,
            device_id=user.device_id,
            bu_id=body.bu_id,
        )


@router.post("/sign-out", status_code=204)
def sign_out(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    device_id: Annotated[str, Depends(get_device_id)],
) -> Response:
    with rls_connection(user) as conn:
        me_service.sign_out(conn, app_user_id=user.app_user_id, device_id=device_id)
        return Response(status_code=204)
