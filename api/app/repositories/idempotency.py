"""Stored Idempotency-Keys (migration 0003)."""

import json
from typing import Any
from uuid import UUID

from app.core.db import Conn


async def lock(conn: Conn, tenant_id: UUID, user_id: UUID, key: UUID) -> None:
    """Two requests with one key run one after the other: the second sees the first's answer."""
    await conn.execute(
        "SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))",
        (f"idempotency:{tenant_id}:{user_id}:{key}",),
    )


async def find(conn: Conn, tenant_id: UUID, user_id: UUID, key: UUID) -> dict[str, Any] | None:
    """The stored answer, if the key is still within its 24 hours."""
    cur = await conn.execute(
        "SELECT operation, request_hash, status_code, headers, body FROM idempotency_key"
        " WHERE tenant_id = %s AND user_id = %s AND key = %s AND expires_at > now()",
        (tenant_id, user_id, key),
    )
    return await cur.fetchone()


async def save(
    conn: Conn,
    *,
    tenant_id: UUID,
    user_id: UUID,
    key: UUID,
    operation: str,
    request_hash: str,
    status_code: int,
    headers: dict[str, str],
    body: bytes,
) -> None:
    """An expired row with the same key is replaced."""
    await conn.execute(
        "DELETE FROM idempotency_key WHERE tenant_id = %s AND user_id = %s AND key = %s",
        (tenant_id, user_id, key),
    )
    await conn.execute(
        "INSERT INTO idempotency_key (tenant_id, user_id, key, operation, request_hash,"
        " status_code, headers, body, expires_at)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb, %s, now() + interval '24 hours')",
        (
            tenant_id,
            user_id,
            key,
            operation,
            request_hash,
            status_code,
            json.dumps(headers),
            body,
        ),
    )


async def delete_expired(conn: Conn) -> int:
    cur = await conn.execute("DELETE FROM idempotency_key WHERE expires_at <= now()")
    return cur.rowcount
