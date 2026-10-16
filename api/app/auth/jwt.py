from __future__ import annotations

import time
from typing import Any

import httpx
import jwt
from fastapi import HTTPException, status
from jwt import PyJWKClient

from app.config import Settings, get_settings

_ALLOWED_AZP = frozenset({"pixorex-web", "pixorex-mobile"})
_jwks_client: PyJWKClient | None = None
_jwks_fetched_at = 0.0


def _client(settings: Settings) -> PyJWKClient:
    global _jwks_client, _jwks_fetched_at
    now = time.time()
    if _jwks_client is None or now - _jwks_fetched_at > 3600:
        # Reach Keycloak; inside Docker use service hostname in kc_issuer.
        _jwks_client = PyJWKClient(settings.jwks_url, cache_keys=True)
        _jwks_fetched_at = now
    return _jwks_client


def verify_access_token(token: str, settings: Settings | None = None) -> dict[str, Any]:
    settings = settings or get_settings()
    try:
        key = _client(settings).get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            key.key,
            algorithms=["RS256"],
            audience="pixorex-api",
            issuer=settings.issuer_for_validation,
            options={"require": ["exp", "iss", "sub"]},
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"title": "Unauthorized", "detail": str(exc)},
        ) from exc

    azp = claims.get("azp")
    if azp not in _ALLOWED_AZP:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"title": "Unauthorized", "detail": "Invalid authorized party"},
        )

    app_user_id = claims.get("app_user_id") or claims.get("preferred_username")
    tenant_id = claims.get("tenant_id")
    if not app_user_id or not tenant_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"title": "Unauthorized", "detail": "Token missing app_user_id or tenant_id"},
        )
    claims["app_user_id"] = str(app_user_id)
    claims["tenant_id"] = str(tenant_id)
    return claims


def keycloak_reachable(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    url = f"{settings.kc_issuer.rstrip('/')}/.well-known/openid-configuration"
    try:
        r = httpx.get(url, timeout=3.0)
        return r.status_code == 200
    except httpx.HTTPError:
        return False
