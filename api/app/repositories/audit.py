"""audit_log rows (BC-07). Written in the same transaction as the change they describe."""

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
