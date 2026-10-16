from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import Settings, get_settings

log = logging.getLogger(__name__)


class KeycloakAdmin:
    """Client-credentials calls to Keycloak Admin REST (pixorex-api-admin)."""

    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()
        self._token: str | None = None

    def _access_token(self) -> str:
        if not self.settings.kc_api_admin_secret:
            raise RuntimeError("KC_API_ADMIN_SECRET is not set")
        data = {
            "grant_type": "client_credentials",
            "client_id": self.settings.kc_api_admin_client_id,
            "client_secret": self.settings.kc_api_admin_secret,
        }
        r = httpx.post(self.settings.token_url, data=data, timeout=15.0)
        r.raise_for_status()
        self._token = r.json()["access_token"]
        return self._token

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self._access_token()}", "Content-Type": "application/json"}

    def find_user_id_by_username(self, username: str) -> str | None:
        r = httpx.get(
            f"{self.settings.admin_base}/users",
            params={"username": username, "exact": "true"},
            headers=self._headers(),
            timeout=15.0,
        )
        r.raise_for_status()
        users = r.json()
        return users[0]["id"] if users else None

    def find_user_id_by_email(self, email: str) -> str | None:
        r = httpx.get(
            f"{self.settings.admin_base}/users",
            params={"email": email, "exact": "true"},
            headers=self._headers(),
            timeout=15.0,
        )
        r.raise_for_status()
        users = r.json()
        return users[0]["id"] if users else None

    def ensure_user(
        self,
        *,
        app_user_id: str,
        email: str,
        tenant_id: str,
        realm_roles: list[str],
        enabled: bool = True,
        email_verified: bool = False,
        phone_number: str | None = None,
        phone_verified: bool = False,
        first_name: str | None = None,
        last_name: str | None = None,
    ) -> str:
        """Create or update a Keycloak user. username = app_user_id. Returns Keycloak user id."""
        attrs: dict[str, list[str]] = {
            "app_user_id": [app_user_id],
            "tenant_id": [tenant_id],
        }
        if phone_number:
            attrs["phone_number"] = [phone_number]
            attrs["phone_verified"] = ["true" if phone_verified else "false"]

        body: dict[str, Any] = {
            "username": app_user_id,
            "email": email,
            "enabled": enabled,
            "emailVerified": email_verified,
            "attributes": attrs,
        }
        if first_name:
            body["firstName"] = first_name
        if last_name:
            body["lastName"] = last_name

        existing = self.find_user_id_by_username(app_user_id) or self.find_user_id_by_email(email)
        if existing:
            # Do not rename username on update (Keycloak rejects conflicting renames).
            update = {k: v for k, v in body.items() if k != "username"}
            r = httpx.put(
                f"{self.settings.admin_base}/users/{existing}",
                headers=self._headers(),
                json=update,
                timeout=15.0,
            )
            r.raise_for_status()
            kc_id = existing
        else:
            r = httpx.post(
                f"{self.settings.admin_base}/users",
                headers=self._headers(),
                json=body,
                timeout=15.0,
            )
            if r.status_code == 409:
                kc_id = self.find_user_id_by_email(email) or self.find_user_id_by_username(app_user_id)
                if not kc_id:
                    r.raise_for_status()
                update = {k: v for k, v in body.items() if k != "username"}
                put = httpx.put(
                    f"{self.settings.admin_base}/users/{kc_id}",
                    headers=self._headers(),
                    json=update,
                    timeout=15.0,
                )
                put.raise_for_status()
            elif r.status_code not in (201, 204):
                r.raise_for_status()
            else:
                kc_id = self.find_user_id_by_username(app_user_id)
                if not kc_id:
                    raise RuntimeError(f"Keycloak user {app_user_id} created but not found")

        self._assign_realm_roles(kc_id, realm_roles)
        return kc_id

    def _assign_realm_roles(self, keycloak_user_id: str, role_names: list[str]) -> None:
        if not role_names:
            return
        available = httpx.get(
            f"{self.settings.admin_base}/users/{keycloak_user_id}/role-mappings/realm/available",
            headers=self._headers(),
            timeout=15.0,
        )
        available.raise_for_status()
        by_name = {r["name"]: r for r in available.json()}
        # Also fetch existing so we don't fail if already assigned
        existing = httpx.get(
            f"{self.settings.admin_base}/users/{keycloak_user_id}/role-mappings/realm",
            headers=self._headers(),
            timeout=15.0,
        )
        existing.raise_for_status()
        have = {r["name"] for r in existing.json()}
        to_add = []
        for name in role_names:
            if name in have:
                continue
            if name not in by_name:
                # Role might only appear in realm roles list
                roles = httpx.get(
                    f"{self.settings.admin_base}/roles/{name}",
                    headers=self._headers(),
                    timeout=15.0,
                )
                roles.raise_for_status()
                to_add.append(roles.json())
            else:
                to_add.append(by_name[name])
        if not to_add:
            return
        r = httpx.post(
            f"{self.settings.admin_base}/users/{keycloak_user_id}/role-mappings/realm",
            headers=self._headers(),
            json=to_add,
            timeout=15.0,
        )
        r.raise_for_status()
