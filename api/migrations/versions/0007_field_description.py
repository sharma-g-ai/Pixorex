"""Fields get a plain-text description (change request of 18 Nov 2026, step 1: expand).

docs/proposals/change-request-field-description-nov-2026.md. A BU Admin (or AI assisted
schema discovery) writes what the field is and where it sits on the label; it is sent to the
AI with every scan of the type. Optional, at most 500 characters.

DDL only: the field freeze trigger fires on row changes, not on ALTER TABLE, so published
types are untouched. No grant or RLS change (table-level grants, existing policy).

Revision ID: 0007
Revises: 0006
"""

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None

SQL = """
ALTER TABLE field_definition
  ADD COLUMN description text
  CONSTRAINT field_definition_description_length CHECK (char_length(description) <= 500);
"""


def upgrade() -> None:
    op.get_bind().connection.driver_connection.execute(SQL)
