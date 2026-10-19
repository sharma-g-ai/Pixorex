"""Outbox runner (FR-6.2, ARCHITECTURE §8): runs work that follows a commit, at least once.

Events are claimed one at a time with FOR UPDATE SKIP LOCKED, so several workers never take
the same one. A failure retries with exponential backoff (1, 2, 4... minutes, at most an
hour); after MAX_ATTEMPTS the event is failed and stays for inspection."""

import smtplib
from collections.abc import Awaitable, Callable
from typing import Any
from uuid import UUID

import structlog
from botocore.exceptions import BotoCoreError, ClientError

from app.auth.context import set_context
from app.core.db import Conn, Pool
from app.repositories.exports import BUILD_EVENT
from app.repositories.notifications import EMAIL_EVENT
from app.services import mail
from app.workers import export_files
from app.workers.settings import WorkerSettings

MAX_ATTEMPTS = 6
_log = structlog.get_logger("pixorex.worker.outbox")
Sender = Callable[..., Awaitable[None]]


async def _claim(conn: Conn, event_types: list[str]) -> dict[str, Any] | None:
    """Only events this worker can handle: others (e.g. AI extraction before its runner
    exists) stay pending instead of failing."""
    cur = await conn.execute(
        "SELECT id, tenant_id, event_type, payload, attempts FROM outbox_event"
        " WHERE status = 'pending' AND next_run_at <= now() AND event_type = ANY(%s)"
        " ORDER BY next_run_at LIMIT 1 FOR UPDATE SKIP LOCKED",
        (event_types,),
    )
    return await cur.fetchone()


async def _email_notification(
    conn: Conn, settings: WorkerSettings, event: dict[str, Any], send: Sender
) -> None:
    """The email copy of a bell notification (FR-6.3); sets emailed_at once sent."""
    payload = event["payload"]
    recipient = UUID(payload["recipient_user_id"])
    # The notification policy shows a row only to its recipient.
    await set_context(conn, tenant_id=event["tenant_id"], user_id=recipient)
    cur = await conn.execute(
        "SELECT n.title, n.body, n.emailed_at, u.email, u.status FROM notification n"
        " JOIN app_user u ON u.id = n.recipient_user_id WHERE n.id = %s",
        (payload["notification_id"],),
    )
    row = await cur.fetchone()
    if row is None or row["emailed_at"] is not None or row["status"] == "removed":
        return  # gone, already sent, or the person was removed: nothing to send
    text = f"{row['body']}\n\n" if row["body"] else ""
    await send(
        settings,
        to=row["email"],
        subject=row["title"],
        text=f"{text}Open Pixorex: {mail.web_link(settings)}\n",
    )
    await conn.execute(
        "UPDATE notification SET emailed_at = now() WHERE id = %s", (payload["notification_id"],)
    )


HANDLERS = {EMAIL_EVENT: _email_notification, BUILD_EVENT: export_files.build}
# Runs when an event is failed for good, so nothing waits on it for ever.
ON_GIVE_UP = {BUILD_EVENT: export_files.give_up}
RETRYABLE = (OSError, smtplib.SMTPException, LookupError, BotoCoreError, ClientError)


async def run_due(
    pool: Pool, settings: WorkerSettings, *, send: Sender = mail.send_email, limit: int = 50
) -> int:
    """Runs up to `limit` due events; returns how many were handled."""
    handled = 0
    for _ in range(limit):
        async with pool.connection() as conn, conn.transaction():
            event = await _claim(conn, list(HANDLERS))
            if event is None:
                return handled
            handler = HANDLERS.get(event["event_type"])
            try:
                if handler is None:
                    raise LookupError(f"no handler for {event['event_type']}")
                async with conn.transaction():  # a savepoint: a failure keeps the claim
                    await handler(conn, settings, event, send)
                await conn.execute(
                    "UPDATE outbox_event SET status = 'done', attempts = attempts + 1"
                    " WHERE id = %s",
                    (event["id"],),
                )
            except RETRYABLE as exc:
                attempts = event["attempts"] + 1
                _log.warning(
                    "outbox_event_failed",
                    event_type=event["event_type"],
                    attempts=attempts,
                    error=type(exc).__name__,
                )
                await conn.execute(
                    "UPDATE outbox_event SET attempts = %s,"
                    " status = CASE WHEN %s >= %s THEN 'failed' ELSE 'pending' END,"
                    " next_run_at = now() + least(interval '1 minute' * power(2, %s - 1),"
                    "   interval '1 hour') WHERE id = %s",
                    (attempts, attempts, MAX_ATTEMPTS, attempts, event["id"]),
                )
                give_up = ON_GIVE_UP.get(event["event_type"])
                if attempts >= MAX_ATTEMPTS and give_up is not None:
                    await give_up(conn, event)
            handled += 1
    return handled
