"""Contracts 3.19-3.22: the notification bell and the audit log."""

from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Response

from app.auth.context import SignedIn
from app.core.paging import Cursor, Limit
from app.services import activity

router = APIRouter(tags=["Activity"])


@router.get("/me/notifications", operation_id="listNotifications")
async def list_notifications(
    session: SignedIn, unread_only: bool = False, cursor: Cursor = None, limit: Limit = 25
) -> activity.NotificationPage:
    return await activity.notifications(
        session, unread_only=unread_only, cursor=cursor, limit=limit
    )


@router.post("/me/notifications/read-all", operation_id="markAllNotificationsRead", status_code=204)
async def mark_all_read(session: SignedIn) -> Response:
    await activity.mark_all_read(session)
    return Response(status_code=204)


@router.post(
    "/me/notifications/{notification_id}/read",
    operation_id="markNotificationRead",
    status_code=204,
)
async def mark_read(notification_id: UUID, session: SignedIn) -> Response:
    await activity.mark_read(session, notification_id)
    return Response(status_code=204)


@router.get("/audit-log", operation_id="listAuditLog")
async def audit_log(
    session: SignedIn,
    bu_id: UUID | None = None,
    category: activity.Category | None = None,
    since: Annotated[date | None, Query(alias="from")] = None,
    until: Annotated[date | None, Query(alias="to")] = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> activity.AuditPage:
    return await activity.audit_log(
        session,
        bu_id=bu_id,
        category=category,
        since=since,
        until=until,
        cursor=cursor,
        limit=limit,
    )
