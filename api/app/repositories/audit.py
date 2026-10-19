"""audit_log rows (BC-07). Written in the same transaction as the change they describe."""

import json
from datetime import datetime
from typing import Any
from uuid import UUID

from app.core.db import Conn


async def record(
    conn: Conn,
    *,
    tenant_id: UUID,
    actor_user_id: UUID | None,
    category: str,
    action: str,
    summary: str,
    bu_id: UUID | None = None,
    object_type: str | None = None,
    object_id: UUID | None = None,
) -> None:
    """summary is the frozen sentence the audit log screen shows; keep it free of tokens."""
    await conn.execute(
        "INSERT INTO audit_log (tenant_id, bu_id, actor_type, actor_user_id, category, action,"
        " summary, object_type, object_id) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)",
        (
            tenant_id,
            bu_id,
            "user" if actor_user_id else "system",
            actor_user_id,
            category,
            action,
            summary,
            object_type,
            object_id,
        ),
    )


async def record_event(
    conn: Conn,
    *,
    tenant_id: UUID,
    actor_user_id: UUID | None,
    category: str,
    action: str,
    summary: str,
    details: dict[str, Any],
    occurred_at: datetime,
    object_type: str | None = None,
    object_id: UUID | None = None,
) -> None:
    """A row for something that happened elsewhere (a Keycloak event), at its own time."""
    await conn.execute(
        "INSERT INTO audit_log (tenant_id, actor_type, actor_user_id, category, action, summary,"
        " details, occurred_at, object_type, object_id)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s, %s)",
        (
            tenant_id,
            "user" if actor_user_id else "system",
            actor_user_id,
            category,
            action,
            summary,
            json.dumps(details),
            occurred_at,
            object_type,
            object_id,
        ),
    )


async def has_detail(conn: Conn, *, tenant_id: UUID, category: str, key: str, value: str) -> bool:
    cur = await conn.execute(
        "SELECT 1 FROM audit_log WHERE tenant_id = %s AND category = %s AND details->>%s = %s"
        " LIMIT 1",
        (tenant_id, category, key, value),
    )
    return await cur.fetchone() is not None
