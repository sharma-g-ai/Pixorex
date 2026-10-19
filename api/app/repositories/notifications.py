"""Bell notifications (FR-6.3). Written in the same transaction as the change they report.

TODO (PX-10-T01 worker): the email copy goes through the outbox worker, which is not built;
emailed_at stays empty until then."""

from uuid import UUID

from app.core.db import Conn


async def notify(
    conn: Conn,
    *,
    tenant_id: UUID,
    recipient: UUID,
    kind: str,
    title: str,
    object_type: str,
    object_id: UUID,
    bu_id: UUID | None = None,
    body: str | None = None,
) -> None:
    await conn.execute(
        "INSERT INTO notification (tenant_id, recipient_user_id, bu_id, kind, object_type,"
        " object_id, title, body) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
        (tenant_id, recipient, bu_id, kind, object_type, object_id, title, body),
    )
