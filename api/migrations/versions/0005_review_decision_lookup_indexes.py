"""Indexes for the technician's batch view (contracts 3.11 and 3.15, screens T 74 and T 77).

The batch screen shows each technician's own decision in the batch ("you approved") and,
when the BU Admin changed it, the replacing decision. Both are found through columns that
had no index: review_decision.batch_id and review_decision.overrides_decision_id. Indexes
only: no new table or column (data model unchanged).

Revision ID: 0005
Revises: 0004
"""

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None

SQL = """
CREATE INDEX IF NOT EXISTS ix_review_decision_batch
  ON review_decision (batch_id) WHERE batch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_review_decision_overrides
  ON review_decision (overrides_decision_id) WHERE overrides_decision_id IS NOT NULL;
"""


def upgrade() -> None:
    op.get_bind().connection.driver_connection.execute(SQL)


def downgrade() -> None:
    raise NotImplementedError("Forward-only.")
