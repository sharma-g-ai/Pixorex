"""Synthetic demo data (SPEC-PX-04 REQ-04.06). Local and test databases only.

Tenant A matches the Keycloak test users in keycloak/scripts/seed-users.json (same
app_user ids, tenant id and emails), so signing in locally finds these rows. It has
3 units; Plant 11 has no BU Admin and a pending invite. Tenant B has no Keycloak users;
it is there so isolation between tenants can be seen and tested.
Invented names, demo.local emails, 555-01xx phone numbers. No real customer data.

Run after migrations, as the owner role:
    PIXOREX_MIGRATIONS_DATABASE_URL=postgresql://pixorex_owner:local-only@localhost:5433/pixorex \
        uv run python scripts/seed_synthetic.py

Fixed IDs make it safe to run twice: rows that already exist are left alone.
"""

import hashlib
import os
import secrets
import sys
import uuid
from typing import Any

import psycopg

TENANT_A = uuid.UUID("7e1d2c3b-0000-4000-8000-00000000a001")  # = seed-users.json tenantId


def _id(name: str) -> uuid.UUID:
    """Same ID on every run for rows Keycloak doesn't know about."""
    return uuid.uuid5(uuid.NAMESPACE_URL, f"pixorex-seed/{name}")


def _kc(n: int) -> uuid.UUID:
    """App user ids of the Keycloak seed users (their usernames)."""
    return uuid.UUID(f"7e1d2c3b-0000-4000-8000-{n:012d}")


TENANT_B = _id("tenant/b")
TENANTS = [(TENANT_A, "Demo Coatings"), (TENANT_B, "Demo Adhesives")]
UNITS = {
    "p04": (TENANT_A, "Plant 04 — Coatings", "Cleveland"),
    "p05": (TENANT_A, "Plant 05 — Powder Coatings", "Toledo"),
    "p11": (TENANT_A, "Plant 11 — Resins", "Houston"),
    "b01": (TENANT_B, "Plant B1 — Sealants", "Atlanta"),
}
# roles: (role, unit or None, removed). The first unit role is the primary one.
USERS: list[dict[str, Any]] = [
    {
        "id": _kc(1),
        "tenant": TENANT_A,
        "name": "Erin Admin",
        "email": "ea@demo.local",
        "status": "invited",
        "roles": [("enterprise_admin", None, False)],
    },
    {
        "id": _kc(2),
        "tenant": TENANT_A,
        "name": "Bo Plant04",
        "email": "buadmin.p04@demo.local",
        "status": "active",
        "roles": [("bu_admin", "p04", False)],
    },
    {
        "id": _kc(3),
        "tenant": TENANT_A,
        "name": "Tara Tech",
        "email": "tech1@demo.local",
        "status": "active",
        "phone": "+15550100001",
        "phone_verified": True,
        "roles": [("field_technician", "p04", False)],
    },
    {
        "id": _kc(4),
        "tenant": TENANT_A,
        "name": "Theo Invited",
        "email": "tech2@demo.local",
        "status": "invited",
        "phone": "+15550100002",
        "phone_verified": False,
        "roles": [("field_technician", "p04", False)],
    },
    {
        "id": _kc(5),
        "tenant": TENANT_A,
        "name": "Dana Dual",
        "email": "dual@demo.local",
        "status": "active",
        "phone": "+15550100003",
        "phone_verified": True,
        "roles": [("bu_admin", "p05", False), ("field_technician", "p04", False)],
    },
    {
        "id": _kc(6),
        "tenant": TENANT_A,
        "name": "Gus Removed",
        "email": "gone@demo.local",
        "status": "removed",
        "roles": [("field_technician", "p05", True)],
    },
    {
        "id": _id("user/b-ea"),
        "tenant": TENANT_B,
        "name": "Jo Other",
        "email": "ea@demo-b.local",
        "status": "active",
        "roles": [("enterprise_admin", None, False)],
    },
    {
        "id": _id("user/b-admin"),
        "tenant": TENANT_B,
        "name": "Sam Other",
        "email": "admin@demo-b.local",
        "status": "active",
        "roles": [("bu_admin", "b01", False)],
    },
]
# Plant 11 has no BU Admin; its invite is pending. The link is never printed or stored.
INVITES = [("p11", "m.lopez@demo.local", "bu_admin", _kc(1))]


def seed(conn: psycopg.Connection) -> None:
    for tenant_id, name in TENANTS:
        conn.execute(
            "INSERT INTO tenant (id, name, package, status) VALUES (%s, %s, 'standard', 'active')"
            " ON CONFLICT (id) DO NOTHING",
            (tenant_id, name),
        )
    for key, (tenant_id, name, facility) in UNITS.items():
        bu = _id(f"unit/{key}")
        conn.execute(
            "INSERT INTO business_unit (id, tenant_id, name, facility_name, status)"
            " VALUES (%s, %s, %s, %s, 'active') ON CONFLICT (id) DO NOTHING",
            (bu, tenant_id, name, facility),
        )
        # Every unit gets its default process and an unpublished location tree (REQ-04.08).
        conn.execute(
            "INSERT INTO business_process (id, tenant_id, bu_id, name, is_default)"
            " VALUES (%s, %s, %s, 'Default', true) ON CONFLICT (id) DO NOTHING",
            (_id(f"process/{key}"), tenant_id, bu),
        )
        conn.execute(
            "INSERT INTO location_hierarchy_version (id, tenant_id, bu_id)"
            " VALUES (%s, %s, %s) ON CONFLICT (id) DO NOTHING",
            (_id(f"locations/{key}"), tenant_id, bu),
        )
    for user in USERS:
        _seed_user(conn, user)
    for unit, email, role, invited_by in INVITES:
        conn.execute(
            "INSERT INTO invite (id, tenant_id, bu_id, email, role, token_hash, invited_by,"
            " expires_at) VALUES (%s, %s, %s, %s, %s, %s, %s, now() + interval '18 hours')"
            " ON CONFLICT (id) DO NOTHING",
            (
                _id(f"invite/{unit}"),
                UNITS[unit][0],
                _id(f"unit/{unit}"),
                email,
                role,
                hashlib.sha256(secrets.token_bytes(32)).hexdigest(),
                invited_by,
            ),
        )


def _seed_user(conn: psycopg.Connection, user: dict[str, Any]) -> None:
    unit_keys = [unit for _, unit, removed in user["roles"] if unit and not removed]
    conn.execute(
        "INSERT INTO app_user (id, tenant_id, email, full_name, phone_number, phone_verified_at,"
        " status, last_bu_id) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)"
        " ON CONFLICT (id) DO NOTHING",
        (
            user["id"],
            user["tenant"],
            user["email"],
            user["name"],
            user.get("phone"),
            "2026-10-01T00:00:00Z" if user.get("phone_verified") else None,
            user["status"],
            _id(f"unit/{unit_keys[0]}") if unit_keys else None,
        ),
    )
    for i, (role, unit, removed) in enumerate(user["roles"]):
        bu = _id(f"unit/{unit}") if unit else None
        conn.execute(
            "INSERT INTO user_unit_role (id, tenant_id, user_id, bu_id, role, is_primary,"
            " removed_at) VALUES (%s, %s, %s, %s, %s, %s, %s) ON CONFLICT (id) DO NOTHING",
            (
                _id(f"role/{user['id']}/{unit}"),
                user["tenant"],
                user["id"],
                bu,
                role,
                i == 0 and not removed,
                "2026-10-01T00:00:00Z" if removed else None,
            ),
        )
        # business_unit.bu_admin_user_id follows from the trigger of migration 0002.


def main() -> None:
    if os.environ.get("PIXOREX_ENV") in ("staging", "production"):
        sys.exit("Refusing to seed: synthetic data is for local and test databases only.")
    url = os.environ.get("PIXOREX_MIGRATIONS_DATABASE_URL")
    if not url:
        sys.exit("Set PIXOREX_MIGRATIONS_DATABASE_URL (the owner role).")
    with psycopg.connect(url) as conn:  # one transaction: all or nothing
        seed(conn)
    print(f"Seeded {len(TENANTS)} tenants, {len(UNITS)} units, {len(USERS)} users.")


if __name__ == "__main__":
    main()
