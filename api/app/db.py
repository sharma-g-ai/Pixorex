from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

from psycopg import Connection
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.config import get_settings

_pool: ConnectionPool | None = None


def init_pool() -> None:
    global _pool
    if _pool is None:
        _pool = ConnectionPool(
            conninfo=get_settings().database_url,
            min_size=1,
            max_size=10,
            kwargs={"row_factory": dict_row},
            open=True,
        )


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


@contextmanager
def connection() -> Iterator[Connection]:
    if _pool is None:
        init_pool()
    assert _pool is not None
    with _pool.connection() as conn:
        yield conn


def set_rls(
    conn: Connection,
    *,
    tenant_id: str,
    user_id: str,
    bu_ids: list[str],
    is_ea: bool,
) -> None:
    """SET LOCAL for the current transaction (RLS in 09_rls.sql)."""
    bu = ",".join(bu_ids)
    conn.execute("SELECT set_config('app.tenant_id', %s, true)", (tenant_id,))
    conn.execute("SELECT set_config('app.user_id', %s, true)", (user_id,))
    conn.execute("SELECT set_config('app.bu_ids', %s, true)", (bu,))
    conn.execute("SELECT set_config('app.is_ea', %s, true)", ("true" if is_ea else "false",))
