"""Bell notifications (FR-6.3), each with an email copy queued in the outbox (FR-6.2).
Both are written in the same transaction as the change they report; the worker sends the
email and sets notification.emailed_at.

One statement writes both, and never reads the notification back: RLS lets only its
recipient read it, and RETURNING would need that read for someone else's notification."""

from uuid import UUID

from app.core.db import Conn

EMAIL_EVENT = "notification.email"


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
        "WITH n AS (SELECT uuidv7() AS id),"
        " note AS (INSERT INTO notification (id, tenant_id, recipient_user_id, bu_id, kind,"
        "   object_type, object_id, title, body)"
        "   SELECT n.id, %(tenant)s, %(recipient)s, %(bu)s, %(kind)s, %(object_type)s,"
        "   %(object_id)s, %(title)s, %(body)s FROM n)"
        " INSERT INTO outbox_event (tenant_id, event_type, payload)"
        " SELECT %(tenant)s, %(event)s, jsonb_build_object('notification_id', n.id::text,"
        "   'recipient_user_id', %(recipient)s::text) FROM n",
        {
            "tenant": tenant_id,
            "recipient": recipient,
            "bu": bu_id,
            "kind": kind,
            "object_type": object_type,
            "object_id": object_id,
            "title": title,
            "body": body,
            "event": EMAIL_EVENT,
        },
    )
