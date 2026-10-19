"""Keycloak Admin REST calls with the pixorex-api-admin service account (BC-01).

A0, HUMAN-WRITTEN LOGIC. Ported from Iswarya's api/app/auth/keycloak_admin.py (branch
feature/PX-01-T08-invite-signin-api): username = app_user_id, attributes app_user_id and
tenant_id (and phone for technicians), realm role pixorex-web or pixorex-mobile.
Changed in the port: async, one shared HTTP client, the service token is reused until
shortly before it expires. Needs architect review (CONSTITUTION §5).
"""

import time
from dataclasses import dataclass
from typing import Any

import httpx
from pydantic import SecretStr


class CrossTenantUserError(Exception):
    """The email already signs in to another tenant."""


@dataclass(frozen=True)
class KeycloakUser:
    app_user_id: str
    tenant_id: str
    email: str
    realm_role: str  # pixorex-web (admins) or pixorex-mobile (technicians)
    email_verified: bool = False
    phone_number: str | None = None
    first_name: str | None = None
    last_name: str | None = None


def _body(user: KeycloakUser, current: dict[str, Any] | None) -> dict[str, Any]:
    """The user representation to send. Keycloak replaces the whole attribute map on update,
    so the current attributes are kept (added in the port), and nothing verified is reset:
    a phone counts as unverified only when the number changes.
    """
    current = current or {}
    attributes: dict[str, list[str]] = {
        **current.get("attributes", {}),
        "app_user_id": [user.app_user_id],
        "tenant_id": [user.tenant_id],
    }
    if user.phone_number and attributes.get("phone_number") != [user.phone_number]:
        attributes |= {"phone_number": [user.phone_number], "phone_verified": ["false"]}
    body: dict[str, Any] = {
        "email": user.email,
        "enabled": True,
        "emailVerified": user.email_verified or bool(current.get("emailVerified")),
        "attributes": attributes,
    }
    if user.first_name:
        body["firstName"] = user.first_name
    if user.last_name:
        body["lastName"] = user.last_name
    return body


class KeycloakAdmin:
    def __init__(
        self,
        *,
        realm_url: str,
        client_id: str,
        client_secret: SecretStr | None,
        http: httpx.AsyncClient,
    ) -> None:
        """realm_url: the realm as this process reaches it, e.g. http://keycloak:8080/realms/pixorex."""
        self._realm_url = realm_url.rstrip("/")
        self._client_id = client_id
        self._client_secret = client_secret
        self._http = http
        root, realm = self._realm_url.rsplit("/realms/", 1)
        self._base = f"{root}/admin/realms/{realm}"
        self._token = ""
        self._token_expires = 0.0

    async def ensure_user(self, user: KeycloakUser) -> str:
        """Create or update the user; returns the Keycloak user id."""
        found = await self._find(username=user.app_user_id) or await self._find(email=user.email)
        if found and found.get("attributes", {}).get("tenant_id", [user.tenant_id]) != [
            user.tenant_id
        ]:
            # Added in the port: never take over a login that belongs to another tenant.
            raise CrossTenantUserError
        if found is None:
            created = await self._call(
                "POST", "/users", json={"username": user.app_user_id, **_body(user, None)}
            )
            if created.status_code != 409:  # 409: created meanwhile, update it below
                created.raise_for_status()
            found = await self._find(username=user.app_user_id)
            if found is None:
                raise RuntimeError("Keycloak user was created but cannot be found")
        kc_id = str(found["id"])
        # The username is never renamed: Keycloak rejects conflicting renames.
        updated = await self._call("PUT", f"/users/{kc_id}", json=_body(user, found))
        updated.raise_for_status()
        await self._add_realm_role(kc_id, user.realm_role)
        return kc_id

    async def brute_force_status(self, kc_id: str) -> dict[str, Any]:
        """{numFailures, disabled, lastFailure (ms), lastIPFailure}: the temporary lock state
        (docs/keycloak.md 5.3). Added for the lock audit row (5.4)."""
        response = await self._call("GET", f"/attack-detection/brute-force/users/{kc_id}")
        response.raise_for_status()
        status: dict[str, Any] = response.json()
        return status

    async def disable_login(
        self, *, app_user_id: str, keycloak_user_id: str | None = None
    ) -> None:
        """Stop IdP sign-in immediately (docs/keycloak.md §6.11: full removal).

        Sets enabled=false, ends SSO sessions, and revokes pixorex-mobile offline tokens.
        No-op when the person never had a Keycloak user (invite never accepted).
        """
        found = await self._user(keycloak_user_id) if keycloak_user_id else None
        if found is None:
            found = await self._find(username=app_user_id)
        if found is None:
            return
        kc_id = str(found["id"])
        disabled = {**found, "enabled": False}
        disabled.pop("id", None)  # Keycloak rejects id in the PUT body
        updated = await self._call("PUT", f"/users/{kc_id}", json=disabled)
        updated.raise_for_status()
        logged_out = await self._call("POST", f"/users/{kc_id}/logout")
        logged_out.raise_for_status()
        # No mobile consent yet (web-only admin) → 404; that is fine.
        consents = await self._call("DELETE", f"/users/{kc_id}/consents/pixorex-mobile")
        if consents.status_code not in (204, 404):
            consents.raise_for_status()

    async def _user(self, keycloak_user_id: str) -> dict[str, Any] | None:
        response = await self._call("GET", f"/users/{keycloak_user_id}")
        if response.status_code == 404:
            return None
        response.raise_for_status()
        return response.json()

    async def _find(self, **query: str) -> dict[str, Any] | None:
        response = await self._call("GET", "/users", params={**query, "exact": "true"})
        response.raise_for_status()
        users: list[dict[str, Any]] = response.json()
        return users[0] if users else None

    async def _add_realm_role(self, kc_id: str, role_name: str) -> None:
        mapped = await self._call("GET", f"/users/{kc_id}/role-mappings/realm")
        mapped.raise_for_status()
        if any(r["name"] == role_name for r in mapped.json()):
            return
        # The service account manages users but may not read /roles (view-realm), so the role
        # is taken from the user's assignable roles, as Iswarya's original code did.
        available = await self._call("GET", f"/users/{kc_id}/role-mappings/realm/available")
        available.raise_for_status()
        role = next((r for r in available.json() if r["name"] == role_name), None)
        if role is None:
            raise RuntimeError(f"Realm role {role_name} does not exist")
        added = await self._call("POST", f"/users/{kc_id}/role-mappings/realm", json=[role])
        added.raise_for_status()

    async def _call(self, method: str, path: str, **kwargs: Any) -> httpx.Response:
        headers = {"Authorization": f"Bearer {await self._service_token()}"}
        return await self._http.request(
            method, f"{self._base}{path}", headers=headers, timeout=15.0, **kwargs
        )

    async def _service_token(self) -> str:
        if time.monotonic() < self._token_expires:
            return self._token
        secret = self._client_secret
        if secret is None:
            raise RuntimeError("PIXOREX_KEYCLOAK_ADMIN_SECRET is not set")
        response = await self._http.post(
            f"{self._realm_url}/protocol/openid-connect/token",
            data={
                "grant_type": "client_credentials",
                "client_id": self._client_id,
                "client_secret": secret.get_secret_value(),
            },
            timeout=15.0,
        )
        response.raise_for_status()
        payload = response.json()
        self._token = str(payload["access_token"])
        self._token_expires = time.monotonic() + int(payload.get("expires_in", 60)) - 30
        return self._token
