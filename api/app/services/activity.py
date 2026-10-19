"""Audit log (contract 3.22, decision D-06) and the notification bell (3.19-3.21)."""

from datetime import date, datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel

from app.auth.context import Session
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.repositories import activity

Category = Literal[
    "sign_in",
    "users",
    "locations",
    "equipment_types",
    "review",
    "override",
    "escalation",
    "export",
    "retention",
]
NotificationKind = Literal[
    "scan_waiting_1d",
    "scan_waiting_1w",
    "scans_escalated",
    "unit_no_bu_admin",
    "escalation_reminder",
    "batch_delegated",
    "batch_no_progress",
    "batch_reminder",
    "batch_reassigned",
    "batch_taken_back",
    "scan_removed_from_batch",
    "scan_approved",
    "scan_rejected",
    "decision_overridden",
    "ea_delegated_in_unit",
    "invite_expired",
    "export_ready",
]


class AuditEntry(BaseModel):
    occurred_at: datetime
    actor_type: Literal["user", "system"]
    actor_name: str | None
    bu_name: str | None
    category: Category
    summary: str
    action: str
    object_type: str
    object_id: UUID | None
    details: dict[str, Any]


class AuditPage(BaseModel):
    items: list[AuditEntry]
    page: PageInfo


class Notification(BaseModel):
    notification_id: UUID
    kind: NotificationKind
    title: str
    body: str | None
    bu_id: UUID | None
    object_type: str
    object_id: UUID | None  # always set by the code that creates notifications
    created_at: datetime
    read_at: datetime | None
    emailed_at: datetime | None


class NotificationPage(BaseModel):
    items: list[Notification]
    page: PageInfo
    unread_count: int


async def audit_log(
    session: Session,
    *,
    bu_id: UUID | None,
    category: Category | None,
    since: date | None,
    until: date | None,
    cursor: str | None,
    limit: int,
) -> AuditPage:
    """D-06: the EA reads every unit (and tenant-wide rows); a BU Admin reads the units they
    run. RLS alone would also show units where they are only a technician."""
    caller = session.caller
    if caller.is_ea:
        units = None
    else:
        caller.require_admin()
        units = sorted(caller.units("bu_admin"))
        if bu_id is not None and bu_id not in units:
            raise ProblemError(403, "forbidden")
    if since and until and since > until:
        raise ProblemError(400, "validation", "'from' must not be after 'to'.")
    rows = await activity.audit_page(
        session.conn,
        units=units,
        bu_id=bu_id,
        category=category,
        since=since,
        until=until,
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return AuditPage(
        items=[
            AuditEntry(
                **{**r, "object_type": r["object_type"] or "", "details": r["details"] or {}}
            )
            for r in rows
        ],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["occurred_at"].isoformat(), rows[-1]["id"])
            if more
            else None
        ),
    )


async def notifications(
    session: Session, *, unread_only: bool, cursor: str | None, limit: int
) -> NotificationPage:
    caller = session.caller
    rows = await activity.notifications_page(
        session.conn,
        user_id=caller.user_id,
        unread_only=unread_only,
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return NotificationPage(
        items=[Notification(**{**r, "object_type": r["object_type"] or ""}) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(
                rows[-1]["created_at"].isoformat(), rows[-1]["notification_id"]
            )
            if more
            else None
        ),
        unread_count=await activity.unread_count(session.conn, caller.user_id),
    )


async def mark_read(session: Session, notification_id: UUID) -> None:
    if not await activity.mark_read(session.conn, session.caller.user_id, notification_id):
        raise ProblemError(404, "not-found")


async def mark_all_read(session: Session) -> None:
    await activity.mark_all_read(session.conn, session.caller.user_id)
