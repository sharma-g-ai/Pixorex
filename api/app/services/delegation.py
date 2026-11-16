"""Delegation console (contracts 3.8-3.14, PRD FR-5.6, FR-5.7)."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.auth import signed_urls
from app.auth.context import Session
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.core.storage import StorageConfig
from app.repositories import audit, notifications
from app.repositories import delegation as repo
from app.services.review import require_unit_admin

MAX_BATCH = 50


class Delegate(BaseModel):
    user_id: UUID
    full_name: str
    open_review_count: int
    own_scans_in_selection: int


class DelegatePage(BaseModel):
    items: list[Delegate]
    page: PageInfo


class NewBatch(BaseModel):
    assigned_to: UUID
    scan_ids: list[UUID] = Field(min_length=1, max_length=MAX_BATCH)


class Excluded(BaseModel):
    scan_id: UUID
    reason: Literal["own_scan"]


class Created(BaseModel):
    batch_id: UUID
    batch_no: str
    assigned_scan_ids: list[UUID]
    excluded: list[Excluded]


class Batch(BaseModel):
    batch_id: UUID
    batch_no: str
    assigned_to_name: str
    created_by_name: str
    scan_count: int
    decided_count: int
    open_count: int  # still assigned: what is left to review
    overridden_count: int  # the technician's decisions here that a BU Admin changed
    overridden_unseen_count: int  # of those, not seen yet (0 for anyone but that technician)
    created_at: datetime
    reminded_at: datetime | None
    status: Literal["active", "completed", "taken_back"]


class BatchPage(BaseModel):
    items: list[Batch]
    page: PageInfo


RejectCategory = Literal["image_unclear", "data_correction_needed", "wrong_equipment_type", "other"]


class DecisionOverride(BaseModel):
    """The BU Admin's decision that replaced the technician's (contract 3.7; T 77)."""

    decision: Literal["approved", "rejected"]
    reject_category: RejectCategory | None
    note: str | None
    decided_by_name: str
    decided_at: datetime
    notification_id: UUID | None  # "Got it" marks it read (3.21)
    seen: bool


class BatchDecision(BaseModel):
    """The assigned technician's own decision on a scan in this batch (T 74 "you approved")."""

    decision: Literal["approved", "rejected"]
    reject_category: RejectCategory | None
    decided_at: datetime
    override: DecisionOverride | None


class Assignment(BaseModel):
    scan_id: UUID
    record_no: str
    status: Literal["assigned", "decided", "removed"]
    removed_reason: Literal["taken_back", "reassigned", "admin_decided", "user_removed"] | None
    equipment_type_name: str
    captured_by_name: str
    location_path: str
    flag_count: int
    submitted_at: datetime
    thumbnail_url: str | None  # signed, 15 minutes; only after the access check
    my_decision: BatchDecision | None  # only for the assigned technician


def _assignment(row: dict, storage: StorageConfig | None) -> Assignment:  # type: ignore[type-arg]
    mine = None
    if row["my_decision"] is not None:
        override = None
        if row["ov_decision"] is not None:
            override = DecisionOverride(
                decision=row["ov_decision"],
                reject_category=row["ov_category"],
                note=row["ov_note"],
                decided_by_name=row["ov_by"],
                decided_at=row["ov_at"],
                notification_id=row["ov_notification_id"],
                seen=bool(row["ov_seen"]),
            )
        mine = BatchDecision(
            decision=row["my_decision"],
            reject_category=row["my_category"],
            decided_at=row["my_decided_at"],
            override=override,
        )
    return Assignment(
        scan_id=row["scan_id"],
        record_no=row["record_no"],
        status=row["status"],
        removed_reason=row["removed_reason"],
        equipment_type_name=row["equipment_type_name"],
        captured_by_name=row["captured_by_name"],
        location_path=row["location_path"],
        flag_count=row["flag_count"],
        submitted_at=row["submitted_at"],
        thumbnail_url=signed_urls.photo_url(storage, row["photo_key"])
        if storage is not None and row["photo_key"]
        else None,
        my_decision=mine,
    )


class BatchDetail(BaseModel):
    batch: Batch
    assignments: list[Assignment]


class Reassign(BaseModel):
    assigned_to: UUID


class Reassigned(BaseModel):
    batch_id: UUID
    assigned_to: UUID
    excluded: list[Excluded]


class TakeBack(BaseModel):
    message: str | None = Field(default=None, max_length=1000)


class Reminded(BaseModel):
    reminded_at: datetime


async def delegates(
    session: Session, bu_id: UUID, *, scan_ids: list[UUID], cursor: str | None, limit: int
) -> DelegatePage:
    require_unit_admin(session, bu_id)
    rows = await repo.delegates(
        session.conn, bu_id=bu_id, scan_ids=scan_ids, after=decode_cursor(cursor, 2), limit=limit
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return DelegatePage(
        items=[Delegate(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["full_name"], rows[-1]["user_id"]) if more else None
        ),
    )


async def _assignee(session: Session, user_id: UUID, bu_id: UUID) -> None:
    if not await repo.is_technician_of(session.conn, user_id, bu_id):
        raise ProblemError(400, "validation", "Pick a technician of this unit.")


async def _audit(session: Session, bu_id: UUID, action: str, summary: str, batch_id: UUID) -> None:
    await audit.record(
        session.conn,
        tenant_id=session.caller.tenant_id,
        actor_user_id=session.caller.user_id,
        bu_id=bu_id,
        category="review",
        action=action,
        summary=summary,
        object_type="review_batch",
        object_id=batch_id,
    )


async def _notify(
    session: Session,
    recipient: UUID,
    kind: str,
    title: str,
    batch_id: UUID,
    bu_id: UUID,
    body: str | None = None,
) -> None:
    await notifications.notify(
        session.conn,
        tenant_id=session.caller.tenant_id,
        recipient=recipient,
        kind=kind,
        title=title,
        body=body,
        object_type="review_batch",
        object_id=batch_id,
        bu_id=bu_id,
    )


async def create_batch(session: Session, bu_id: UUID, body: NewBatch) -> Created:
    """Contract 3.9: waiting scans without an open assignment; the technician's own scans are
    left out (excluded)."""
    caller, conn = session.caller, session.conn
    require_unit_admin(session, bu_id)
    await _assignee(session, body.assigned_to, bu_id)
    wanted = list(dict.fromkeys(body.scan_ids))
    scans = await repo.scans_for_batch(conn, bu_id, wanted)
    if len(scans) != len(wanted):
        raise ProblemError(404, "not-found", "A scan is not in this unit.")
    if any(s["review_status"] != "waiting_for_approval" for s in scans):
        raise ProblemError(409, "invalid-state", "Every scan must be waiting for approval.")
    if any(s["assigned"] for s in scans):
        raise ProblemError(409, "already-assigned", "A scan is already in an open batch.")
    excluded = [s["id"] for s in scans if s["technician_id"] == body.assigned_to]
    assigned = [s for s in wanted if s not in excluded]
    if not assigned:
        raise ProblemError(400, "validation", "Every scan was captured by that technician.")
    batch_no = await repo.next_batch_no(conn, caller.tenant_id)
    batch_id = await repo.create_batch(
        conn,
        tenant_id=caller.tenant_id,
        bu_id=bu_id,
        batch_no=batch_no,
        assigned_to=body.assigned_to,
        created_by=caller.user_id,
    )
    await repo.assign(
        conn,
        tenant_id=caller.tenant_id,
        batch_id=batch_id,
        scan_ids=assigned,
        assigned_to=body.assigned_to,
    )
    count = f"{len(assigned)} {'scan' if len(assigned) == 1 else 'scans'}"
    await _notify(
        session,
        body.assigned_to,
        "batch_delegated",
        f"{batch_no}: {count} to review",
        batch_id,
        bu_id,
    )
    if bu_id not in caller.units("bu_admin"):  # an EA delegated inside someone's unit
        admin = await repo.bu_admin_of(conn, bu_id)
        if admin:
            await _notify(
                session,
                admin,
                "ea_delegated_in_unit",
                f"The Enterprise Admin delegated {batch_no} ({count})",
                batch_id,
                bu_id,
            )
    await _audit(session, bu_id, "batch.created", f"Delegated {batch_no} ({count})", batch_id)
    return Created(
        batch_id=batch_id,
        batch_no=batch_no,
        assigned_scan_ids=assigned,
        excluded=[Excluded(scan_id=s, reason="own_scan") for s in excluded],
    )


async def list_batches(
    session: Session, bu_id: UUID, *, status: str | None, cursor: str | None, limit: int
) -> BatchPage:
    require_unit_admin(session, bu_id)
    rows = await repo.batches(
        session.conn, bu_id=bu_id, status=status, after=decode_cursor(cursor, 2), limit=limit
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return BatchPage(
        items=[Batch(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["created_at"].isoformat(), rows[-1]["batch_id"])
            if more
            else None
        ),
    )


async def my_batches(session: Session, *, cursor: str | None, limit: int) -> BatchPage:
    """Contract 3.15: the active batches given to the calling technician, and any other one
    while it holds a decision of theirs a BU Admin changed that they haven't seen (T 77)."""
    if not session.caller.units("field_technician"):
        raise ProblemError(403, "forbidden")
    rows = await repo.batches(
        session.conn,
        assigned_to=session.caller.user_id,
        status="active",
        or_unseen_override=True,
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return BatchPage(
        items=[Batch(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["created_at"].isoformat(), rows[-1]["batch_id"])
            if more
            else None
        ),
    )


async def get_batch(
    session: Session, batch_id: UUID, storage: StorageConfig | None = None
) -> BatchDetail:
    """Contract 3.11: admins of the unit, or the assigned technician. Thumbnails are signed
    only after this check (BC-09); my_decision is filled only for the assigned technician."""
    row = await repo.batch(session.conn, batch_id)
    if row is None:
        raise ProblemError(404, "not-found")
    caller = session.caller
    technician = row["assigned_to"] == caller.user_id
    if not technician:
        require_unit_admin(session, row["bu_id"])
    rows = await repo.assignments(
        session.conn, batch_id, technician=caller.user_id if technician else None
    )
    return BatchDetail(batch=Batch(**row), assignments=[_assignment(a, storage) for a in rows])


async def _active(session: Session, batch_id: UUID) -> dict:  # type: ignore[type-arg]
    row = await repo.batch(session.conn, batch_id, lock=True)
    if row is None:
        raise ProblemError(404, "not-found")
    require_unit_admin(session, row["bu_id"])
    if row["status"] != "active":
        raise ProblemError(409, "invalid-state", "This batch is no longer active.")
    return row


async def reassign(session: Session, batch_id: UUID, assigned_to: UUID) -> Reassigned:
    """Contract 3.12: open assignments close (reassigned) and reopen for the new technician,
    minus their own scans."""
    conn = session.conn
    row = await _active(session, batch_id)
    await _assignee(session, assigned_to, row["bu_id"])
    if assigned_to == row["assigned_to"]:
        raise ProblemError(400, "validation", "The batch is already with that technician.")
    open_rows = await repo.open_assignments(conn, batch_id)
    excluded = [a["scan_id"] for a in open_rows if a["technician_id"] == assigned_to]
    await repo.remove_open(conn, batch_id, "reassigned")
    await repo.assign(
        conn,
        tenant_id=row["tenant_id"],
        batch_id=batch_id,
        scan_ids=[a["scan_id"] for a in open_rows if a["scan_id"] not in excluded],
        assigned_to=assigned_to,
    )
    await repo.set_assignee(conn, batch_id, assigned_to)
    await _notify(
        session,
        assigned_to,
        "batch_reassigned",
        f"{row['batch_no']} is now yours to review",
        batch_id,
        row["bu_id"],
    )
    await _notify(
        session,
        row["assigned_to"],
        "batch_reassigned",
        f"{row['batch_no']} was given to someone else",
        batch_id,
        row["bu_id"],
    )
    await _audit(
        session, row["bu_id"], "batch.reassigned", f"Reassigned {row['batch_no']}", batch_id
    )
    return Reassigned(
        batch_id=batch_id,
        assigned_to=assigned_to,
        excluded=[Excluded(scan_id=s, reason="own_scan") for s in excluded],
    )


async def take_back(session: Session, batch_id: UUID, message: str | None) -> None:
    row = await _active(session, batch_id)
    text = (message or "").strip() or None
    await repo.remove_open(session.conn, batch_id, "taken_back")
    await repo.take_back(session.conn, batch_id, text)
    await _notify(
        session,
        row["assigned_to"],
        "batch_taken_back",
        f"{row['batch_no']} was taken back",
        batch_id,
        row["bu_id"],
        body=text,
    )
    await _audit(
        session, row["bu_id"], "batch.taken_back", f"Took back {row['batch_no']}", batch_id
    )


async def remind(session: Session, batch_id: UUID) -> Reminded:
    row = await _active(session, batch_id)
    reminded_at = await repo.remind(session.conn, batch_id)
    await _notify(
        session,
        row["assigned_to"],
        "batch_reminder",
        f"Reminder: {row['batch_no']} is waiting for you",
        batch_id,
        row["bu_id"],
    )
    return Reminded(reminded_at=reminded_at)
