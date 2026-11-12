"""Outbox runner (FR-6.2, ARCHITECTURE §8): runs work that follows a commit, at least once.

Events are claimed one at a time with FOR UPDATE SKIP LOCKED, so several workers never take
the same one. A failure retries with exponential backoff (1, 2, 4... minutes, at most an
hour); after MAX_ATTEMPTS the event is failed and stays for inspection. Any error from a
handler counts as a failure, so one bad event never holds up the events behind it.

Most handlers run inside the claim transaction. An event type that waits on a slow call (AI
extraction) is leased instead: the claim pushes next_run_at ahead and commits, the slow step
runs with no transaction open, and a second short transaction saves its result. A worker that
dies leaves an event that comes due again when its lease ends."""

import asyncio
import smtplib
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any
from uuid import UUID

import structlog
from botocore.exceptions import BotoCoreError, ClientError

from app.auth.context import set_context
from app.core.db import Conn, Pool
from app.repositories.exports import BUILD_EVENT
from app.repositories.notifications import EMAIL_EVENT
from app.repositories.scans import EXTRACTION_EVENT
from app.services import mail
from app.workers import export_files, extraction
from app.workers.settings import WorkerSettings

MAX_ATTEMPTS = 6
_log = structlog.get_logger("pixorex.worker.outbox")
Sender = Callable[..., Awaitable[None]]
GiveUp = Callable[[Conn, dict[str, Any]], Awaitable[None]]


async def _claim(conn: Conn, event_types: list[str]) -> dict[str, Any] | None:
    """Only events this worker can handle: others (e.g. AI extraction before its runner
    exists) stay pending instead of failing. waited_ms is how long the event has existed."""
    cur = await conn.execute(
        "SELECT id, tenant_id, event_type, payload, attempts,"
        " (extract(epoch FROM now() - created_at) * 1000)::bigint AS waited_ms"
        " FROM outbox_event"
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


HANDLERS = {
    EMAIL_EVENT: _email_notification,
    BUILD_EVENT: export_files.build,
}


@dataclass(frozen=True)
class Leased:
    """An event type whose slow step runs with no transaction open (see the module docstring).
    lease_s: how long other workers stay off the event. prepare: reads what the step needs,
    inside the claim. call: the slow step itself. finish: saves its result, in a second short
    transaction."""

    lease_s: Callable[[WorkerSettings], float]
    prepare: Callable[[Conn, WorkerSettings, dict[str, Any]], Awaitable[Any]]
    call: Callable[[WorkerSettings, Any], Awaitable[Any]]
    finish: Callable[[Conn, dict[str, Any], Any, Any], Awaitable[None]]


LEASED = {
    EXTRACTION_EVENT: Leased(
        extraction.lease_s, extraction.prepare, extraction.call, extraction.finish
    ),
}
# Runs when an event is failed for good, so nothing waits on it for ever.
ON_GIVE_UP = {BUILD_EVENT: export_files.give_up, EXTRACTION_EVENT: extraction.give_up}
# Failures to expect (mail, storage and network trouble) are logged as a warning. Any other
# error is a bug: it is counted and backed off the same way, and logged with its traceback.
RETRYABLE = (OSError, smtplib.SMTPException, LookupError, BotoCoreError, ClientError)
# Which events each worker role takes: AI extraction runs in its own container, so a scan
# backlog never holds up emails or exports.
EVENTS = {
    "all": [*HANDLERS, *LEASED],
    "extraction": [EXTRACTION_EVENT],
    "general": list(HANDLERS),
}


async def _done(conn: Conn, event: dict[str, Any]) -> None:
    await conn.execute(
        "UPDATE outbox_event SET status = 'done', attempts = attempts + 1"
        " WHERE id = %s AND status = 'pending'",
        (event["id"],),
    )


async def _clean_up(conn: Conn, event: dict[str, Any], give_up: GiveUp) -> None:
    """Runs the clean-up of an event failed for good in a savepoint: if the clean-up fails
    too, the event stays failed instead of being rolled back and claimed again."""
    try:
        async with conn.transaction():
            await give_up(conn, event)
    except Exception:
        _log.exception("outbox_give_up_failed", event_type=event["event_type"])


async def _fail(conn: Conn, event: dict[str, Any], exc: Exception) -> None:
    """One failed try, whatever the error: count it and back off. After MAX_ATTEMPTS the event
    is failed and the clean-up of its type runs."""
    cur = await conn.execute(
        "UPDATE outbox_event SET attempts = attempts + 1,"
        " status = CASE WHEN attempts + 1 >= %s THEN 'failed' ELSE 'pending' END,"
        " next_run_at = now() + least(interval '1 minute' * power(2, attempts), interval '1 hour')"
        " WHERE id = %s AND status = 'pending' RETURNING attempts",
        (MAX_ATTEMPTS, event["id"]),
    )
    row = await cur.fetchone()
    if row is None:
        return  # another worker finished the event meanwhile
    details = {
        "event_type": event["event_type"],
        "attempts": row["attempts"],
        "error": type(exc).__name__,
    }
    if isinstance(exc, RETRYABLE):
        _log.warning("outbox_event_failed", **details)
    else:
        _log.error("outbox_event_failed", exc_info=exc, **details)
    give_up = ON_GIVE_UP.get(event["event_type"])
    if row["attempts"] >= MAX_ATTEMPTS and give_up is not None:
        await _clean_up(conn, event, give_up)


async def _handle(
    conn: Conn, settings: WorkerSettings, event: dict[str, Any], send: Sender
) -> None:
    """Runs the event's handler inside the claim transaction (emails, export builds)."""
    handler = HANDLERS.get(event["event_type"])
    try:
        if handler is None:
            raise LookupError(f"no handler for {event['event_type']}")
        async with conn.transaction():  # a savepoint: a failure keeps the claim
            await handler(conn, settings, event, send)
        await _done(conn, event)
    except Exception as exc:  # any error is one failed try, so the queue never stalls
        await _fail(conn, event, exc)


async def _lease(
    conn: Conn, settings: WorkerSettings, event: dict[str, Any], leased: Leased
) -> Any | None:
    """In the claim transaction: leases the event and reads what the slow step needs. None when
    the event is finished already: nothing to do for it, or a failed try was recorded."""
    try:
        await conn.execute(
            "UPDATE outbox_event SET next_run_at = now() + make_interval(secs => %s) WHERE id = %s",
            (leased.lease_s(settings), event["id"]),
        )
        async with conn.transaction():  # a savepoint, like a handler's
            job = await leased.prepare(conn, settings, event)
    except Exception as exc:
        await _fail(conn, event, exc)
        return None
    if job is None:
        await _done(conn, event)
    return job


async def _call_and_finish(
    pool: Pool, settings: WorkerSettings, event: dict[str, Any], leased: Leased, job: Any
) -> None:
    """The slow step with no transaction open, then its result in a short second transaction."""
    try:
        outcome = await leased.call(settings, job)
        async with pool.connection() as conn, conn.transaction():
            await leased.finish(conn, event, job, outcome)
            await _done(conn, event)
    except Exception as exc:
        async with pool.connection() as conn, conn.transaction():
            await _fail(conn, event, exc)


async def _run_next(pool: Pool, settings: WorkerSettings, send: Sender) -> bool:
    """Claims the oldest due event of this worker's role and runs it; False if none was due."""
    async with pool.connection() as conn, conn.transaction():
        event = await _claim(conn, EVENTS[settings.worker_role])
        if event is None:
            return False
        leased = LEASED.get(event["event_type"])
        if leased is None:
            await _handle(conn, settings, event, send)
            return True
        job = await _lease(conn, settings, event, leased)
    # The claim is committed: the lease is stored and the connection is back in the pool.
    if job is not None:
        await _call_and_finish(pool, settings, event, leased, job)
    return True


async def run_due(
    pool: Pool,
    settings: WorkerSettings,
    *,
    send: Sender = mail.send_email,
    limit: int = 50,
    stop: asyncio.Event | None = None,
) -> int:
    """Runs up to `limit` due events of this worker's role, one after another; returns how many
    were handled. Once `stop` is set, no further event is taken."""
    handled = 0
    while handled < limit and not (stop is not None and stop.is_set()):
        if not await _run_next(pool, settings, send):
            break
        handled += 1
    return handled
