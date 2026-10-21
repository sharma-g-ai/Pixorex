"""Test identities and tokens shared by the integration tests (one signing key per run)."""

import time
from typing import Any

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

from app.auth.keycloak_admin import KeycloakUser

TENANT_A = "7e1d2c3b-0000-4000-8000-00000000a001"
ERIN, BO, TARA, THEO, DANA, GUS = (f"7e1d2c3b-0000-4000-8000-{n:012d}" for n in range(1, 7))


_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ISSUER = "http://127.0.0.1:1/realms/pixorex"


class FakeJwks:
    async def key(self, kid: str) -> jwt.PyJWK:
        if kid != "test":
            raise KeyError(kid)
        return jwt.PyJWK.from_dict(
            {**jwt.algorithms.RSAAlgorithm.to_jwk(_KEY.public_key(), as_dict=True), "kid": "test"}
        )


class FakeKeycloak:
    def __init__(self) -> None:
        self.users: list[KeycloakUser] = []
        self.lock: dict[str, Any] = {"disabled": False, "numFailures": 0}
        self.disabled: list[str] = []

    async def ensure_user(self, user: KeycloakUser) -> str:
        self.users.append(user)
        return f"kc-{user.app_user_id}"

    async def brute_force_status(self, kc_id: str) -> dict[str, Any]:
        return self.lock

    async def disable_login(self, *, app_user_id: str, keycloak_user_id: str | None = None) -> None:
        self.disabled.append(app_user_id)


def make_token(user_id: str, tenant_id: str = TENANT_A, **overrides: Any) -> str:
    now = int(time.time())
    claims = {
        "iss": ISSUER,
        "aud": "pixorex-api",
        "azp": "pixorex-web",
        "sub": f"kc-{user_id}",
        "app_user_id": user_id,
        "tenant_id": tenant_id,
        "iat": now,
        "exp": now + 300,
        **overrides,
    }
    return jwt.encode(claims, _KEY, algorithm="RS256", headers={"kid": "test"})
