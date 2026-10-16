"""PostgreSQL connection pool (psycopg 3).

Every request that touches tenant data runs in one transaction that first sets the
RLS context with SET LOCAL. That code is the request-context middleware (A0, PX-01-T05);
SET LOCAL ends with the transaction, so a pooled connection never carries it over.
"""

from psycopg import AsyncConnection
from psycopg.rows import DictRow, dict_row
from psycopg_pool import AsyncConnectionPool

from app.core.config import Settings

Conn = AsyncConnection[DictRow]  # every pooled connection returns rows as dicts
Pool = AsyncConnectionPool[Conn]


def create_pool(settings: Settings) -> Pool:
    return AsyncConnectionPool(
        settings.database_url.get_secret_value(),
        connection_class=Conn,
        min_size=settings.db_pool_min,
        max_size=settings.db_pool_max,
        kwargs={"row_factory": dict_row, "application_name": "pixorex-api"},
        # Replace connections the server closed while idle before handing them out.
        check=AsyncConnectionPool.check_connection,
        open=False,
    )
