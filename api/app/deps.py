from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth.jwt import verify_access_token
from app.db import connection, set_rls
from app.services import me as me_service

_bearer = HTTPBearer(auto_error=False)


@dataclass
class CurrentUser:
    app_user_id: UUID
    tenant_id: UUID
    email: str | None
    device_id: str
    azp: str


def get_device_id(x_device_id: Annotated[str | None, Header(alias="X-Device-Id")] = None) -> str:
    if not x_device_id or not x_device_id.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"title": "Bad Request", "detail": "X-Device-Id header is required"},
        )
    return x_device_id.strip()


def get_current_user(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    device_id: Annotated[str, Depends(get_device_id)],
) -> CurrentUser:
    if creds is None or creds.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"title": "Unauthorized", "detail": "Missing bearer token"},
        )
    claims = verify_access_token(creds.credentials)
    return CurrentUser(
        app_user_id=UUID(str(claims["app_user_id"])),
        tenant_id=UUID(str(claims["tenant_id"])),
        email=claims.get("email"),
        device_id=device_id,
        azp=str(claims.get("azp")),
    )


def authed_connection(user: Annotated[CurrentUser, Depends(get_current_user)]):
    """DB connection with RLS locals set from the caller's roles."""
    with connection() as conn:
        with conn.transaction():
            roles = me_service.load_unit_roles(conn, user.app_user_id, bypass_rls=True)
            bu_ids = [str(r["bu_id"]) for r in roles if r.get("bu_id")]
            is_ea = any(r["role"] == "enterprise_admin" for r in roles)
            set_rls(
                conn,
                tenant_id=str(user.tenant_id),
                user_id=str(user.app_user_id),
                bu_ids=bu_ids,
                is_ea=is_ea,
            )
            yield conn, user
