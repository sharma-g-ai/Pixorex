"""Scan IDs become 10 digits: a 9-digit counter per tenant from 100000001, then a Luhn
check digit (1000000040 for scan 4; the apps show 100 000 004 0). Asked for by the lead,
5 Nov 2026, so a scan can be quoted and typed without a wrong digit going unnoticed.

Existing REC-n numbers are renumbered once to the same counter (REC-4 -> 1000000040), so
the order stays the same. Every number from now on must have this shape.

Revision ID: 0004
Revises: 0003
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None

FIRST = 100_000_000  # REC-n becomes counter FIRST + n


def _luhn(payload: str) -> int:
    total = 0
    for i, ch in enumerate(reversed(payload)):
        d = int(ch)
        if i % 2 == 0:
            d = d * 2 - 9 if d > 4 else d * 2
        total += d
    return (10 - total % 10) % 10


def upgrade() -> None:
    conn = op.get_bind().connection.driver_connection
    rows = conn.execute(
        "SELECT id, substring(record_no FROM '^REC-([0-9]+)$')::bigint AS n FROM scan"
        " WHERE record_no ~ '^REC-[0-9]+$'"
    ).fetchall()
    for scan_id, n in rows:
        counter = str(FIRST + n)
        conn.execute(
            "UPDATE scan SET record_no = %s WHERE id = %s", (f"{counter}{_luhn(counter)}", scan_id)
        )
    conn.execute(
        "ALTER TABLE scan ADD CONSTRAINT ck_scan_record_no_digits CHECK (record_no ~ '^[0-9]{10}$')"
    )


def downgrade() -> None:
    conn = op.get_bind().connection.driver_connection
    conn.execute("ALTER TABLE scan DROP CONSTRAINT ck_scan_record_no_digits")
    conn.execute(
        "UPDATE scan SET record_no = 'REC-' || (left(record_no, 9)::bigint - %s)", (FIRST,)
    )
