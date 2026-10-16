"""Token check (app/auth/tokens.py) against a Keycloak-shaped key set."""

import time
from typing import Any

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.auth.tokens import Jwks, verify_access_token
from app.core.problems import ProblemError
from tests.conftest import make_settings

SIGNING = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ENCRYPTION = rsa.generate_private_key(public_exponent=65537, key_size=2048)
SETTINGS = make_settings()
ISSUER = str(SETTINGS.oidc_issuer).rstrip("/")
USER, TENANT = "7e1d2c3b-0000-4000-8000-000000000002", "7e1d2c3b-0000-4000-8000-00000000a001"


def _jwk(key: rsa.RSAPrivateKey, kid: str, use: str) -> dict[str, Any]:
    public = jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key(), as_dict=True)
    return {**public, "kid": kid, "use": use, "alg": "RS256" if use == "sig" else "RSA-OAEP"}


def _jwks() -> tuple[Jwks, list[int]]:
    fetches: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        fetches.append(1)
        keys = [_jwk(SIGNING, "sig-1", "sig"), _jwk(ENCRYPTION, "enc-1", "enc")]
        return httpx.Response(200, json={"keys": keys})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return Jwks("http://keycloak/certs", client), fetches


def _token(key: rsa.RSAPrivateKey = SIGNING, kid: str = "sig-1", **claims: Any) -> str:
    now = int(time.time())
    body = {
        "iss": ISSUER,
        "aud": "pixorex-api",
        "azp": "pixorex-web",
        "sub": "kc-1",
        "app_user_id": USER,
        "tenant_id": TENANT,
        "iat": now,
        "exp": now + 300,
        **claims,
    }
    return jwt.encode(body, key, algorithm="RS256", headers={"kid": kid})


async def test_a_valid_keycloak_token_is_accepted() -> None:
    jwks, _ = _jwks()
    claims = await verify_access_token(_token(), SETTINGS, jwks)
    assert (str(claims.user_id), str(claims.tenant_id), claims.client) == (
        USER,
        TENANT,
        "pixorex-web",
    )


async def test_preferred_username_is_the_fallback_user_id() -> None:
    jwks, _ = _jwks()
    token = _token(app_user_id=None, preferred_username=USER)
    assert str((await verify_access_token(token, SETTINGS, jwks)).user_id) == USER


@pytest.mark.parametrize(
    "token",
    [
        _token(iss="http://elsewhere/realms/pixorex"),
        _token(aud="pixorex-web"),  # an ID token, not an access token for the API
        _token(azp="other-client"),
        _token(exp=int(time.time()) - 120),
        _token(tenant_id=None),
        _token(app_user_id="not-a-uuid"),
        _token(key=ENCRYPTION, kid="enc-1"),  # the encryption key never signs
        _token(key=rsa.generate_private_key(public_exponent=65537, key_size=2048)),  # forged
        "not.a.token",
    ],
)
async def test_bad_tokens_get_401_without_the_reason(token: str) -> None:
    jwks, _ = _jwks()
    with pytest.raises(ProblemError) as caught:
        await verify_access_token(token, SETTINGS, jwks)
    assert (caught.value.status, caught.value.code, caught.value.detail) == (
        401,
        "unauthorized",
        "Sign in again.",
    )


async def test_keys_are_cached_and_unknown_keys_refetch_at_most_every_30_s() -> None:
    jwks, fetches = _jwks()
    for _ in range(3):
        await verify_access_token(_token(), SETTINGS, jwks)
    assert len(fetches) == 1
    for _ in range(3):
        with pytest.raises(ProblemError):
            await verify_access_token(_token(kid="rotated-key"), SETTINGS, jwks)
    assert len(fetches) == 1  # fetched less than 30 s ago: no refetch storm
