"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Created: ${create_date}
"""

from alembic import op

revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
    """)


def downgrade() -> None:
    # Forward-only: fix a bad migration with a new one.
    raise NotImplementedError
