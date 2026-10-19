"""Escalations (contracts 3.16, 3.17, PRD FR-5.8) and all scans (3.18): Enterprise Admin."""

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.auth.context import Session
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.repositories import audit, notifications
from app.repositories import oversight as repo
from app.repositories.delegation import bu_admin_of

Reason = Literal["not_approved_24h", "no_bu_admin"]


class Escalation(BaseModel):
    escalation_id: UUID
    scan_id: UUID
    record_no: str
    bu_id: UUID
    bu_name: str
    equipment_type_name: str
    captured_by_name: str
    reason: Reason
    escalated_at: datetime
    reminded_at: datetime | None
    batch_no: str | None


class EscalationPage(BaseModel):
    items: list[Escalation]
    page: PageInfo


class RemindResult(BaseModel):
    reminded_count: int


class ReviewedBy(BaseModel):
    name: str
    overrode_name: str | None


class ScanAssignment(BaseModel):
    batch_no: str
    assigned_to_name: str


class ScanRow(BaseModel):
    scan_id: UUID
    record_no: str
    bu_name: str
    equipment_type_name: str
    captured_by_name: str
    location_path: str
    review_status: str
    captured_at: datetime
    reviewed_by: ReviewedBy | None
    assignment: ScanAssignment | None
    escalation_reason: Reason | None


class ScanPage(BaseModel):
    items: list[ScanRow]
    page: PageInfo


async def escalations(
    session: Session,
    *,
    bu_id: UUID | None,
    reason: Reason | None,
    open_: bool | None,
    cursor: str | None,
    limit: int,
) -> EscalationPage:
    session.caller.require_ea()
    rows = await repo.escalations(
        session.conn,
        bu_id=bu_id,
        reason=reason,
        open_=open_,
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return EscalationPage(
        items=[Escalation(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(
                rows[-1]["escalated_at"].isoformat(), rows[-1]["escalation_id"]
            )
            if more
            else None
        ),
    )


async def remind_bu_admin(session: Session, bu_id: UUID) -> RemindResult:
    """Contract 3.17: reminds the unit's BU Admin about its open escalations."""
    caller, conn = session.caller, session.conn
    caller.require_ea()
    admin = await bu_admin_of(conn, bu_id)
    if admin is None:
        raise ProblemError(409, "no-bu-admin", "This unit has no BU Admin to remind.")
    count = await repo.remind_open(conn, bu_id)
    if count == 0:
        return RemindResult(reminded_count=0)  # nothing open: no empty reminder
    await notifications.notify(
        conn,
        tenant_id=caller.tenant_id,
        recipient=admin,
        kind="escalation_reminder",
        title=f"Reminder: {count} escalated {'scan is' if count == 1 else 'scans are'} waiting",
        object_type="business_unit",
        object_id=bu_id,
        bu_id=bu_id,
    )
    await audit.record(
        conn,
        tenant_id=caller.tenant_id,
        actor_user_id=caller.user_id,
        bu_id=bu_id,
        category="escalation",
        action="escalation.reminded",
        summary=f"Reminded the BU Admin about {count} escalated scans",
        object_type="business_unit",
        object_id=bu_id,
    )
    return RemindResult(reminded_count=count)


async def all_scans(
    session: Session,
    *,
    bu_id: UUID | None,
    review_status: str | None,
    delegated: bool | None,
    q: str | None,
    since: date | None,
    until: date | None,
    cursor: str | None,
    limit: int,
) -> ScanPage:
    session.caller.require_ea()
    if since and until and since > until:
        raise ProblemError(400, "validation", "'from' must not be after 'to'.")
    rows = await repo.scans(
        session.conn,
        bu_id=bu_id,
        review_status=review_status,
        delegated=delegated,
        q=(q or "").strip() or None,
        since=since,
        until=until,
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return ScanPage(
        items=[
            ScanRow(
                **{k: r[k] for k in ScanRow.model_fields if k in r},
                reviewed_by=ReviewedBy(name=r["reviewer_name"], overrode_name=r["overrode_name"])
                if r["reviewer_name"]
                else None,
                assignment=ScanAssignment(
                    batch_no=r["batch_no"], assigned_to_name=r["assigned_to_name"]
                )
                if r["batch_no"]
                else None,
            )
            for r in rows
        ],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["captured_at"].isoformat(), rows[-1]["scan_id"])
            if more
            else None
        ),
    )
