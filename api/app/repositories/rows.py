"""Small helpers shared by the repositories."""

from uuid import UUID

from psycopg import AsyncCursor
from psycopg.rows import DictRow


async def returned_id(cur: AsyncCursor[DictRow]) -> UUID:
    """The id from INSERT ... RETURNING id."""
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    return UUID(str(row["id"]))
