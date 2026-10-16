"""Create a customer company and its first Enterprise Admin (SPEC-PX-04 REQ-04.05).

Operator-only: run by Amzur from a machine with migration credentials, never over HTTP.

    uv run python scripts/bootstrap_tenant.py --name "Acme Coatings" \\
        --ea-email jane.doe@acme.com --ea-name "Jane Doe"

In Docker Compose:  docker compose run --rm migrate python scripts/bootstrap_tenant.py ...

Settings (environment; in deployed environments they come from Vault, PX-10-T03):
  PIXOREX_MIGRATIONS_DATABASE_URL   owner role (pixorex_owner): the tenant table is not
                                    writable by the API role
  PIXOREX_OIDC_ISSUER               realm URL, e.g. https://id.example.com/realms/pixorex
  PIXOREX_OIDC_INTERNAL_URL         optional: the realm as this machine reaches it
  PIXOREX_KEYCLOAK_ADMIN_SECRET     secret of the pixorex-api-admin client

Order (docs/keycloak.md §6.1): the database rows commit first, then the Keycloak user is
created. If Keycloak fails, run the same command again: an existing company makes no
database changes, and the Keycloak step finds or creates the user by username.
The Enterprise Admin signs in at the web address with an emailed code; that first code
verifies the email and activates the account (D-08).
"""

import argparse
import asyncio
import sys
from dataclasses import dataclass
from pathlib import Path
from uuid import UUID

import httpx
import psycopg
from email_validator import EmailNotValidError, validate_email
from psycopg.rows import dict_row
from pydantic import AnyHttpUrl, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.auth.keycloak_admin import KeycloakAdmin, KeycloakUser

# PRD FR-6.6 defaults at provisioning. The data_kind codes are not fixed by the model or the
# contracts (open point); confirm them before the retention job (SPEC-PX-11) relies on them.
RETENTION_DEFAULTS = {
    "source_images": 30,
    "ai_attempts": 90,
    "approved_records": 2557,  # 7 years, leap days included
    "revision_history": 2557,
    "user_accounts": 90,  # after deactivation
}


class BootstrapSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="PIXOREX_", extra="ignore")

    migrations_database_url: SecretStr
    oidc_issuer: AnyHttpUrl
    oidc_internal_url: AnyHttpUrl | None = None
    keycloak_admin_client_id: str = "pixorex-api-admin"
    keycloak_admin_secret: SecretStr

    @property
    def realm_url(self) -> str:
        return str(self.oidc_internal_url or self.oidc_issuer).rstrip("/")


@dataclass(frozen=True)
class EnterpriseAdmin:
    tenant_id: UUID
    user_id: UUID
    email: str
    full_name: str
    created: bool  # False: the company already existed, nothing was written


def create_company(
    conn: psycopg.Connection, *, name: str, package: str, email: str, full_name: str
) -> EnterpriseAdmin:
    """One transaction: company, Enterprise Admin, retention defaults, audit row."""
    with conn.transaction(), conn.cursor(row_factory=dict_row) as cur:
        existing = cur.execute(
            "SELECT t.id AS tenant_id, u.id AS user_id, u.email, u.full_name"
            " FROM tenant t"
            " LEFT JOIN user_unit_role r ON r.tenant_id = t.id"
            " AND r.role = 'enterprise_admin' AND r.removed_at IS NULL"
            " LEFT JOIN app_user u ON u.id = r.user_id"
            " WHERE lower(t.name) = lower(%s) ORDER BY r.created_at LIMIT 1",
            (name,),
        ).fetchone()
        if existing:
            if existing["user_id"] is None:
                raise SystemExit(f"Company {name!r} exists without an Enterprise Admin.")
            return EnterpriseAdmin(**existing, created=False)

        tenant = cur.execute(
            "INSERT INTO tenant (name, package, status) VALUES (%s, %s, 'active') RETURNING id",
            (name, package),
        ).fetchone()
        assert tenant is not None  # noqa: S101 (RETURNING always returns the row)
        tenant_id = tenant["id"]
        user = cur.execute(
            "INSERT INTO app_user (tenant_id, email, full_name, status)"
            " VALUES (%s, %s, %s, 'invited') RETURNING id",
            (tenant_id, email, full_name),
        ).fetchone()
        assert user is not None  # noqa: S101
        cur.execute(
            "INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role, is_primary)"
            " VALUES (%s, %s, NULL, 'enterprise_admin', true)",
            (tenant_id, user["id"]),
        )
        cur.executemany(
            "INSERT INTO retention_config (tenant_id, bu_id, data_kind, keep_days)"
            " VALUES (%s, NULL, %s, %s)",
            [(tenant_id, kind, days) for kind, days in RETENTION_DEFAULTS.items()],
        )
        cur.execute(
            "INSERT INTO audit_log (tenant_id, actor_type, category, action, summary,"
            " object_type, object_id) VALUES (%s, 'system', 'users', 'tenant.created', %s,"
            " 'tenant', %s)",
            (tenant_id, f"Company set up with Enterprise Admin {email}", tenant_id),
        )
        return EnterpriseAdmin(tenant_id, user["id"], email, full_name, created=True)


async def create_login(settings: BootstrapSettings, admin: EnterpriseAdmin) -> str:
    first, _, last = admin.full_name.partition(" ")
    async with httpx.AsyncClient() as http:
        keycloak = KeycloakAdmin(
            realm_url=settings.realm_url,
            client_id=settings.keycloak_admin_client_id,
            client_secret=settings.keycloak_admin_secret,
            http=http,
        )
        return await keycloak.ensure_user(
            KeycloakUser(
                app_user_id=str(admin.user_id),
                tenant_id=str(admin.tenant_id),
                email=admin.email,
                realm_role="pixorex-web",
                email_verified=False,  # the first sign-in code verifies it (D-08)
                first_name=first or None,
                last_name=last or None,
            )
        )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", required=True, help="company name, as customers see it")
    parser.add_argument("--ea-email", required=True, help="first Enterprise Admin's work email")
    parser.add_argument("--ea-name", required=True, help="their full name")
    parser.add_argument("--package", default="standard")
    args = parser.parse_args(argv)
    try:
        email = validate_email(args.ea_email, check_deliverability=False).normalized.lower()
    except EmailNotValidError as exc:
        raise SystemExit(f"Not a valid email: {exc}") from None
    name, full_name = args.name.strip(), args.ea_name.strip()
    if not name or not full_name:
        raise SystemExit("--name and --ea-name must not be empty.")

    settings = BootstrapSettings()  # type: ignore[call-arg]  # values come from the environment
    with psycopg.connect(settings.migrations_database_url.get_secret_value()) as conn:
        admin = create_company(
            conn, name=name, package=args.package, email=email, full_name=full_name
        )
        print(
            f"{'Created' if admin.created else 'Already exists'}: company {name!r},"
            f" Enterprise Admin {admin.email} (tenant {admin.tenant_id})."
        )
        kc_id = asyncio.run(create_login(settings, admin))
        conn.execute(
            "UPDATE app_user SET keycloak_user_id = %s WHERE id = %s", (kc_id, admin.user_id)
        )
        conn.commit()
    print("Keycloak login ready. They sign in at the web address with an emailed code.")


if __name__ == "__main__":
    main()
