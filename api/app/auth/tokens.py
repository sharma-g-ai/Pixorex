"""Keycloak access-token check (BC-01).

A0, HUMAN-WRITTEN LOGIC. Ported from Iswarya's api/app/auth/jwt.py (branch
feature/PX-01-T08-invite-signin-api). The rules are hers: RS256, audience pixorex-api,
issuer, authorized party pixorex-web or pixorex-mobile, app_user_id and tenant_id claims.
Changed in the port: async key fetch, problem+json errors without the library's reason.
Needs architect review before use beyond local development (CONSTITUTION §5).
"""

import asyncio
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import httpx
import jwt
import structlog

from app.core.config import Settings
from app.core.problems import ProblemError

_log = structlog.get_logger("pixorex.auth")
_KEYS_MAX_AGE_S = 3600
_UNKNOWN_KID_RETRY_S = 30  # a token with a new key id refetches at most this often
_CLOCK_SKEW_S = 30


@dataclass(frozen=True)
class TokenClaims:
    user_id: UUID
    tenant_id: UUID
    client: str  # azp: pixorex-web or pixorex-mobile
    issued_at: datetime


class Jwks:
    """Keycloak's signing keys, cached. Refetched hourly, or when a token names an unknown key."""

    def __init__(self, url: str, http: httpx.AsyncClient) -> None:
        self._url = url
        self._http = http
        self._keys: dict[str, jwt.PyJWK] = {}
        self._fetched_at = float("-inf")  # never fetched
        self._lock = asyncio.Lock()

    def _stale(self, kid: str) -> bool:
        age = time.monotonic() - self._fetched_at
        return age > _KEYS_MAX_AGE_S or (kid not in self._keys and age > _UNKNOWN_KID_RETRY_S)

    async def key(self, kid: str) -> jwt.PyJWK:
        if self._stale(kid):
            async with self._lock:
                if self._stale(kid):  # another request may have refreshed meanwhile
                    await self._refresh()
        return self._keys[kid]  # KeyError: unknown key, the token is rejected

    async def _refresh(self) -> None:
        response = await self._http.get(self._url)
        response.raise_for_status()
        # Signing keys only: Keycloak also publishes an encryption key ("use": "enc").
        keys = [k for k in response.json().get("keys", []) if k.get("use", "sig") == "sig"]
        key_set = jwt.PyJWKSet.from_dict({"keys": keys})
        self._keys = {k.key_id: k for k in key_set.keys if k.key_id}
        self._fetched_at = time.monotonic()


def unauthorized() -> ProblemError:
    return ProblemError(401, "unauthorized", "Sign in again.")


async def verify_access_token(token: str, settings: Settings, jwks: Jwks) -> TokenClaims:
    try:
        kid = jwt.get_unverified_header(token).get("kid") or ""
        key = await jwks.key(kid)
        claims: dict[str, Any] = jwt.decode(
            token,
            key.key,
            algorithms=["RS256"],
            audience=settings.oidc_audience,
            issuer=str(settings.oidc_issuer).rstrip("/"),
            leeway=_CLOCK_SKEW_S,
            options={"require": ["exp", "iat", "iss", "sub", "aud"]},
        )
        if claims.get("azp") not in settings.oidc_clients:
            raise jwt.InvalidTokenError("authorized party")
        # Keycloak usernames are app_user ids, so preferred_username is the fallback.
        user_id = UUID(str(claims.get("app_user_id") or claims.get("preferred_username")))
        tenant_id = UUID(str(claims["tenant_id"]))
    except (jwt.PyJWTError, KeyError, ValueError, httpx.HTTPError) as exc:
        # The reason goes to logs only; callers just see "sign in again".
        _log.info("token_rejected", reason=type(exc).__name__)
        raise unauthorized() from None
    return TokenClaims(
        user_id=user_id,
        tenant_id=tenant_id,
        client=str(claims["azp"]),
        issued_at=datetime.fromtimestamp(int(claims["iat"]), UTC),
    )
