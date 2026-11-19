"""Drop the phone number of users (change request of 19 Nov 2026: sign-in by email only).

Technicians sign in like admins, with a code sent to their email; nobody gives a phone number
any more, so app_user.phone_number (with its unique index and E.164 check) and
phone_verified_at go. Decision D-12 in STATE.md. No code reads these columns any more; the
numbers they held are lost.

Revision ID: 0009
Revises: 0008
"""

from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None

SQL = """
ALTER TABLE app_user
  DROP COLUMN phone_number,
  DROP COLUMN phone_verified_at;
"""


def upgrade() -> None:
    op.get_bind().connection.driver_connection.execute(SQL)
