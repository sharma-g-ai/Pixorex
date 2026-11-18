"""Drop the format rule and the critical flag of fields (change request of 18 Nov 2026,
step 3: contract).

docs/proposals/change-request-field-description-nov-2026.md. The description (0007) replaces
the format rule; "critical" is removed (low-confidence flags already apply to every field).
No code reads these columns any more. The values they held are lost; export them first if
anyone needs them (query in the change request, section 4).

Stored flag reasons 'critical_not_found' and 'format_failed' stay allowed on ai_field_value:
old scans use them, and 'format_failed' still marks a value that does not fit its type.

Revision ID: 0008
Revises: 0007
"""

from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None

SQL = """
ALTER TABLE field_definition
  DROP COLUMN format_rule,
  DROP COLUMN is_critical;
"""


def upgrade() -> None:
    op.get_bind().connection.driver_connection.execute(SQL)
