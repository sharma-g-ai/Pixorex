"""Alembic environment. Plain SQL migrations, no ORM models.

Runs as the owner role from PIXOREX_MIGRATIONS_DATABASE_URL, e.g.
postgresql://pixorex_owner:local-only@localhost:5432/pixorex
(deployed environments get it from Vault, PX-10-T03).
"""

import os

from alembic import context
from sqlalchemy import create_engine

url = os.environ.get("PIXOREX_MIGRATIONS_DATABASE_URL")
if not url:
    raise SystemExit("Set PIXOREX_MIGRATIONS_DATABASE_URL (the owner role) to run migrations.")
# SQLAlchemy needs the driver named; psycopg 3 is the one we use.
url = url.replace("postgresql://", "postgresql+psycopg://", 1)

engine = create_engine(url)
with engine.connect() as connection:
    context.configure(connection=connection, transaction_per_migration=True)
    with context.begin_transaction():
        context.run_migrations()
