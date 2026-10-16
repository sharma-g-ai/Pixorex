"""Baseline: the 31 tables, triggers, grants and RLS of the V3 data model.

Runs the files in migrations/baseline/ in order (see its README). 08 grants and
09 RLS are drafts for architect review (A0).

Revision ID: 0001
Revises:
"""

import re
from pathlib import Path

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

BASELINE = Path(__file__).resolve().parents[1] / "baseline"
FILES = [
    "00_foundation.sql",
    "01_domain1_tenancy.sql",
    "02_domain2_locations.sql",
    "03_domain3_equipment_types.sql",
    "04_domain4_scans.sql",
    "05_domain5_review.sql",
    "06_domain6_audit_ops.sql",
    "07_triggers.sql",
    "08_roles_grants.sql",
    "09_rls.sql",
]
# Each file wraps itself in BEGIN/COMMIT for psql; Alembic already runs this in one transaction.
_TXN = re.compile(r"^\s*(BEGIN|COMMIT)\s*;\s*$", re.MULTILINE | re.IGNORECASE)


def upgrade() -> None:
    # Straight to psycopg with no parameters, so "%" and ":name" in the SQL stay as written.
    conn = op.get_bind().connection.driver_connection
    for name in FILES:
        conn.execute(_TXN.sub("", (BASELINE / name).read_text(encoding="utf-8")))


def downgrade() -> None:
    raise NotImplementedError("Forward-only. To start again: drop and recreate the database.")
