#!/usr/bin/env python3
"""Create a demo tenant + one Enterprise Admin in Postgres and Keycloak (local only)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from psycopg import connect
from psycopg.rows import dict_row

from app.auth.keycloak_admin import KeycloakAdmin
from app.config import get_settings


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", default="Demo Tenant")
    parser.add_argument("--ea-email", required=True)
    parser.add_argument("--ea-name", default="Enterprise Admin")
    args = parser.parse_args()
    settings = get_settings()

    tenant_id = uuid4()
    user_id = uuid4()
    parts = args.ea_name.strip().split(None, 1)
    first, last = parts[0], (parts[1] if len(parts) > 1 else "Admin")

    with connect(settings.database_owner_url, row_factory=dict_row) as conn:
        with conn.transaction():
            exists = conn.execute("SELECT id FROM tenant WHERE name = %s", (args.name,)).fetchone()
            if exists:
                tenant_id = exists["id"]
            else:
                conn.execute(
                    "INSERT INTO tenant (id, name, package, status) VALUES (%s, %s, %s, %s)",
                    (str(tenant_id), args.name, "standard", "active"),
                )

            user = conn.execute(
                "SELECT id FROM app_user WHERE tenant_id = %s AND lower(email) = lower(%s)",
                (str(tenant_id), args.ea_email),
            ).fetchone()
            if user:
                user_id = user["id"]
            else:
                conn.execute(
                    """
                    INSERT INTO app_user (id, tenant_id, email, full_name, status)
                    VALUES (%s, %s, %s, %s, 'active')
                    """,
                    (str(user_id), str(tenant_id), args.ea_email.lower(), args.ea_name),
                )

            uid = str(user_id)
            tid = str(tenant_id)
            role = conn.execute(
                """
                SELECT id FROM user_unit_role
                 WHERE user_id = %s AND role = 'enterprise_admin' AND removed_at IS NULL
                """,
                [uid],
            ).fetchone()
            if not role:
                conn.execute(
                    """
                    INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role, is_primary)
                    VALUES (%s, %s, NULL, 'enterprise_admin', true)
                    """,
                    [tid, uid],
                )

            kc_id = KeycloakAdmin(settings).ensure_user(
                app_user_id=str(user_id),
                email=args.ea_email.lower(),
                tenant_id=str(tenant_id),
                realm_roles=["pixorex-web"],
                enabled=True,
                email_verified=True,
                first_name=first,
                last_name=last,
            )
            conn.execute(
                "UPDATE app_user SET keycloak_user_id = %s, updated_at = now() WHERE id = %s",
                (kc_id, str(user_id)),
            )

    print(f"tenant_id={tenant_id}")
    print(f"app_user_id={user_id}")
    print(f"email={args.ea_email.lower()}")
    print("Sign in on web with this email; code arrives in Mailpit (or realm SMTP).")


if __name__ == "__main__":
    main()
