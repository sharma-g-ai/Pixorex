"""Keycloak admin client (app/auth/keycloak_admin.py) against a fake Admin REST API."""

import json
from typing import Any

import httpx
import pytest
from pydantic import SecretStr

from app.auth.keycloak_admin import CrossTenantUserError, KeycloakAdmin, KeycloakUser

TENANT = "7e1d2c3b-0000-4000-8000-00000000a001"
DANA = "7e1d2c3b-0000-4000-8000-000000000005"


class FakeKeycloak:
    def __init__(self, users: list[dict[str, Any]]) -> None:
        self.users = users
        self.puts: list[dict[str, Any]] = []
        self.role_posts = 0

    def __call__(self, request: httpx.Request) -> httpx.Response:
        path, method = request.url.path, request.method
        if path.endswith("/protocol/openid-connect/token"):
            return httpx.Response(200, json={"access_token": "t", "expires_in": 300})
        if path.endswith("/users") and method == "GET":
            q = request.url.params
            found = [
                u
                for u in self.users
                if ("username" in q and u["username"] == q["username"])
                or ("email" in q and u["email"] == q["email"])
            ]
            return httpx.Response(200, json=found)
        if path.endswith("/users") and method == "POST":
            body = json.loads(request.content)
            self.users.append({**body, "id": f"kc-{len(self.users)}"})
            return httpx.Response(201)
        if "/users/" in path and method == "PUT":
            self.puts.append(json.loads(request.content))
            return httpx.Response(204)
        if path.endswith("/role-mappings/realm") and method == "GET":
            return httpx.Response(200, json=[])
        if path.endswith("/role-mappings/realm/available"):
            roles = [{"id": "r1", "name": "pixorex-web"}, {"id": "r2", "name": "pixorex-mobile"}]
            return httpx.Response(200, json=roles)
        if "/roles/" in path:  # like the real realm: the service account may not read roles
            return httpx.Response(403)
        if path.endswith("/role-mappings/realm") and method == "POST":
            self.role_posts += 1
            return httpx.Response(204)
        return httpx.Response(404)


def _admin(fake: FakeKeycloak) -> KeycloakAdmin:
    return KeycloakAdmin(
        realm_url="http://keycloak/realms/pixorex",
        client_id="pixorex-api-admin",
        client_secret=SecretStr("test-only"),
        http=httpx.AsyncClient(transport=httpx.MockTransport(fake)),
    )


def _dana(**attributes: list[str]) -> dict[str, Any]:
    return {
        "id": "kc-dana",
        "username": DANA,
        "email": "dual@demo.local",
        "emailVerified": True,
        "attributes": {"app_user_id": [DANA], "tenant_id": [TENANT], **attributes},
    }


def _user(**kw: Any) -> KeycloakUser:
    base: dict[str, Any] = {
        "app_user_id": DANA,
        "tenant_id": TENANT,
        "email": "dual@demo.local",
        "realm_role": "pixorex-web",
    }
    return KeycloakUser(**{**base, **kw})


async def test_an_admin_invite_keeps_a_verified_phone_and_email() -> None:
    fake = FakeKeycloak([_dana(phone_number=["+15550100003"], phone_verified=["true"])])
    assert await _admin(fake).ensure_user(_user(email_verified=False)) == "kc-dana"
    sent = fake.puts[-1]
    assert sent["attributes"]["phone_number"] == ["+15550100003"]
    assert sent["attributes"]["phone_verified"] == ["true"]
    assert sent["emailVerified"] is True
    assert "username" not in sent  # never renamed


async def test_the_same_number_stays_verified_a_new_one_does_not() -> None:
    fake = FakeKeycloak([_dana(phone_number=["+15550100003"], phone_verified=["true"])])
    admin = _admin(fake)
    await admin.ensure_user(_user(realm_role="pixorex-mobile", phone_number="+15550100003"))
    assert fake.puts[-1]["attributes"]["phone_verified"] == ["true"]
    await admin.ensure_user(_user(realm_role="pixorex-mobile", phone_number="+15550100077"))
    assert fake.puts[-1]["attributes"]["phone_verified"] == ["false"]


async def test_a_login_of_another_tenant_is_never_taken_over() -> None:
    other = _dana()
    other["attributes"]["tenant_id"] = ["another-tenant"]
    with pytest.raises(CrossTenantUserError):
        await _admin(FakeKeycloak([other])).ensure_user(_user())


async def test_a_new_person_is_created_with_the_app_user_id_as_username() -> None:
    fake = FakeKeycloak([])
    await _admin(fake).ensure_user(_user(email="new@example.com"))
    assert fake.users[0]["username"] == DANA
    assert fake.users[0]["attributes"]["tenant_id"] == [TENANT]
    assert fake.role_posts == 1
