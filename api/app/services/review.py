"""Review queue, scan review, decisions and override (contracts 3.3-3.7, PRD FR-5.3-5.5)."""

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from psycopg.errors import UniqueViolation
from pydantic import BaseModel, Field

from app.auth import signed_urls
from app.auth.context import Session
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.core.storage import StorageConfig
from app.repositories import audit, notifications
from app.repositories import review as repo

QueueFilter = Literal["waiting", "over_1d", "over_1w", "delegated", "decided_by_technicians"]
RejectCategory = Literal["image_unclear", "data_correction_needed", "wrong_equipment_type", "other"]
Role = Literal["bu_admin", "enterprise_admin", "delegated_technician"]


class QueueCounts(BaseModel):
    waiting: int
    over_1d: int
    over_1w: int
    delegated: int
    decided_by_technicians: int
    approved_this_week: int


class QueueItem(BaseModel):
    scan_id: UUID
    record_no: str
    equipment_type_name: str
    captured_by_name: str
    location_path: str
    flag_count: int
    corrected_count: int
    unreadable_count: int
    waiting_since: datetime
    batch_no: str | None
    assigned_to_name: str | None


class ReviewQueue(BaseModel):
    counts: QueueCounts
    items: list[QueueItem]
    page: PageInfo


class Revision(BaseModel):
    revision_id: UUID
    revision_no: int
    origin: Literal["technician_review", "rejection_fix"]
    empty_required_fields: list[str]
    review_status: str


class ReviewField(BaseModel):
    field_key: str
    label: str
    ai_value: str | None
    confidence: float | None
    flag_reasons: list[str]
    technician_value: str | None
    verification_state: str
    unreadable_reason: str | None
    note: str | None


class Decision(BaseModel):
    decision_id: UUID
    revision_id: UUID
    decision: Literal["approved", "rejected"]
    reject_category: str | None
    note: str | None
    decided_by_name: str
    decider_role: Role
    is_current: bool
    overrides_decision_id: UUID | None
    decided_at: datetime


class ScanReview(BaseModel):
    scan_id: UUID
    record_no: str
    equipment_type_name: str
    location_path: str
    captured_by_name: str
    # Each photo carries a 15-minute signed MinIO URL (A0 draft, BC-09). Without storage
    # configured, photos come without "url" and the screen shows none.
    photos: list[dict[str, Any]]
    current_revision: Revision
    fields: list[ReviewField]
    decisions: list[Decision]


class DecisionInput(BaseModel):
    decision: Literal["approved", "rejected"]
    reject_category: RejectCategory | None = None
    note: str | None = Field(default=None, max_length=2000)


class Decided(BaseModel):
    decision_id: UUID
    review_status: str


class Overridden(BaseModel):
    decision_id: UUID


class TechnicianDecision(BaseModel):
    decision_id: UUID
    scan_id: UUID
    record_no: str
    decided_by_name: str
    decision: str
    reject_category: str | None
    decided_at: datetime
    overridden: bool


class TechnicianDecisionPage(BaseModel):
    items: list[TechnicianDecision]
    page: PageInfo


def require_unit_admin(session: Session, bu_id: UUID) -> None:
    """x-roles [bu_admin, enterprise_admin]: the EA, or the BU Admin of this unit."""
    caller = session.caller
    if not caller.is_ea and bu_id not in caller.units("bu_admin"):
        raise ProblemError(403, "forbidden")


def _admin_role(session: Session, bu_id: UUID) -> Role | None:
    caller = session.caller
    if bu_id in caller.units("bu_admin"):
        return "bu_admin"
    return "enterprise_admin" if caller.is_ea else None


def _check_input(body: DecisionInput) -> str | None:
    if body.decision == "rejected" and body.reject_category is None:
        raise ProblemError(400, "validation", "Pick a reason for the rejection.")
    if body.decision == "approved" and body.reject_category is not None:
        raise ProblemError(400, "validation", "An approval has no rejection reason.")
    return (body.note or "").strip() or None


# ---- 3.3 / 3.6 queue and lists ------------------------------------------------------------


async def queue(
    session: Session, bu_id: UUID, *, filter_: QueueFilter, cursor: str | None, limit: int
) -> ReviewQueue:
    require_unit_admin(session, bu_id)
    rows = await repo.queue_items(
        session.conn, bu_id=bu_id, filter_=filter_, after=decode_cursor(cursor, 2), limit=limit
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return ReviewQueue(
        counts=QueueCounts(**await repo.queue_counts(session.conn, bu_id)),
        items=[QueueItem(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["waiting_since"].isoformat(), rows[-1]["scan_id"])
            if more
            else None
        ),
    )


async def technician_decisions(
    session: Session, bu_id: UUID, *, decision: str | None, cursor: str | None, limit: int
) -> TechnicianDecisionPage:
    session.caller.require_bu_admin_of(bu_id)
    rows = await repo.technician_decisions(
        session.conn, bu_id=bu_id, decision=decision, after=decode_cursor(cursor, 2), limit=limit
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return TechnicianDecisionPage(
        items=[TechnicianDecision(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["decided_at"].isoformat(), rows[-1]["decision_id"])
            if more
            else None
        ),
    )


# ---- 3.4 scan review ---------------------------------------------------------------------------


async def _reviewer(
    session: Session, scan_id: UUID, *, lock: bool = False
) -> tuple[dict[str, Any], Role]:
    """Who may review this scan, and in which role. Nobody reviews their own scan (403
    own-scan); an admin of the unit, or the technician it is assigned to; a technician whose
    assignment was closed is a stale reviewer (409)."""
    caller = session.caller
    scan = await repo.scan(session.conn, scan_id, lock=lock)
    if scan is None:
        raise ProblemError(404, "not-found")
    if scan["technician_id"] == caller.user_id:
        raise ProblemError(403, "own-scan", "Nobody reviews their own scan.")
    role = _admin_role(session, scan["bu_id"])
    if role is None:
        if scan["assigned_to"] == caller.user_id:
            role = "delegated_technician"
        elif await repo.had_assignment(session.conn, scan_id, caller.user_id):
            raise ProblemError(409, "invalid-state", "This scan is no longer assigned to you.")
        else:
            raise ProblemError(403, "forbidden")
    return scan, role


def _photo(row: dict[str, Any], storage: StorageConfig | None) -> dict[str, Any]:
    photo: dict[str, Any] = {"photo_no": row["photo_no"]}
    if storage is not None:
        photo["url"] = signed_urls.photo_url(storage, row["object_key"])
    return photo


async def scan_review(
    session: Session, scan_id: UUID, storage: StorageConfig | None = None
) -> ScanReview:
    """Photo links are signed only after the reviewer check above (BC-09)."""
    scan, _ = await _reviewer(session, scan_id)
    if scan["revision_id"] is None:
        raise ProblemError(404, "not-found", "Nothing has been submitted for review yet.")
    return ScanReview(
        scan_id=scan["scan_id"],
        record_no=scan["record_no"],
        equipment_type_name=scan["equipment_type_name"],
        location_path=scan["location_path"],
        captured_by_name=scan["captured_by_name"],
        photos=[_photo(p, storage) for p in await repo.photos(session.conn, scan_id)],
        current_revision=Revision(
            revision_id=scan["revision_id"],
            revision_no=scan["revision_no"],
            origin=scan["origin"],
            empty_required_fields=scan["empty_required_fields"],
            review_status=scan["review_status"],
        ),
        fields=[
            ReviewField(**f)
            for f in await repo.review_fields(
                session.conn, scan["contract_id"], scan["revision_id"]
            )
        ],
        decisions=[Decision(**d) for d in await repo.decisions(session.conn, scan_id)],
    )


# ---- 3.5 decide -------------------------------------------------------------------------------


async def decide(session: Session, scan_id: UUID, body: DecisionInput) -> Decided:
    """The first valid decision wins (409 already-decided for the loser)."""
    caller, conn = session.caller, session.conn
    note = _check_input(body)
    scan, role = await _reviewer(session, scan_id, lock=True)
    if scan["review_status"] != "waiting_for_approval" or scan["revision_id"] is None:
        if scan["current_decision_id"] is not None:
            raise ProblemError(409, "already-decided", "Someone decided this scan first.")
        raise ProblemError(409, "invalid-state", "This scan is not waiting for approval.")
    if body.decision == "approved" and scan["empty_required_fields"]:
        # FR-5.3: a revision sent with required fields empty can't be approved in V1.
        raise ProblemError(409, "invalid-state", "Required fields are empty: reject it for rework.")
    try:
        decision_id = await repo.insert_decision(
            conn,
            tenant_id=caller.tenant_id,
            revision_id=scan["revision_id"],
            decided_by=caller.user_id,
            role=role,
            decision=body.decision,
            reject_category=body.reject_category,
            note=note,
            batch_id=scan["batch_id"] if role == "delegated_technician" else None,
        )
    except UniqueViolation:
        raise ProblemError(409, "already-decided", "Someone decided this scan first.") from None
    await repo.set_review_status(conn, scan_id, body.decision)
    await repo.resolve_escalations(conn, scan_id, decision_id)
    if scan["assignment_id"]:
        delegated = role == "delegated_technician"
        await repo.close_assignment(conn, scan["assignment_id"], decided=delegated)
        await repo.complete_batch_if_done(conn, scan["batch_id"])
        if not delegated:
            await notifications.notify(
                conn,
                tenant_id=caller.tenant_id,
                recipient=scan["assigned_to"],
                kind="scan_removed_from_batch",
                title=f"{scan['record_no']} was decided by an admin",
                body="It's no longer in your batch.",
                object_type="scan",
                object_id=scan_id,
                bu_id=scan["bu_id"],
            )
    await notifications.notify(
        conn,
        tenant_id=caller.tenant_id,
        recipient=scan["technician_id"],
        kind="scan_approved" if body.decision == "approved" else "scan_rejected",
        title=f"{scan['record_no']} was {body.decision}",
        body=_category_text(body.reject_category),
        object_type="scan",
        object_id=scan_id,
        bu_id=scan["bu_id"],
    )
    await audit.record(
        conn,
        tenant_id=caller.tenant_id,
        actor_user_id=caller.user_id,
        bu_id=scan["bu_id"],
        category="review",
        action=f"scan.{body.decision}",
        summary=f"{body.decision.capitalize()} {scan['record_no']}",
        object_type="scan",
        object_id=scan_id,
    )
    return Decided(decision_id=decision_id, review_status=body.decision)


def _category_text(category: str | None) -> str | None:
    return category.replace("_", " ").capitalize() if category else None


# ---- 3.7 override ------------------------------------------------------------------------------


async def override(session: Session, decision_id: UUID, body: DecisionInput) -> Overridden:
    """A BU Admin replaces a delegated technician's current decision with their own."""
    caller, conn = session.caller, session.conn
    note = _check_input(body)
    old = await repo.decision(conn, decision_id, lock=True)
    if old is None:
        raise ProblemError(404, "not-found")
    caller.require_bu_admin_of(old["bu_id"])
    if not old["is_current"] or old["decider_role"] != "delegated_technician":
        raise ProblemError(
            409, "invalid-state", "Only a technician's current decision can be overridden."
        )
    if old["technician_id"] == caller.user_id:
        raise ProblemError(403, "own-scan", "Nobody reviews their own scan.")
    scan = await repo.scan(conn, old["scan_id"], lock=True)
    if scan is None:
        raise ProblemError(404, "not-found")
    if scan["revision_id"] != old["revision_id"]:
        # The scan was fixed and resubmitted since: that new revision waits for its own review.
        raise ProblemError(409, "invalid-state", "The scan was resubmitted since this decision.")
    if body.decision == "approved" and scan["empty_required_fields"]:
        raise ProblemError(409, "invalid-state", "Required fields are empty: reject it for rework.")
    await repo.retire_decision(conn, decision_id)
    new_id = await repo.insert_decision(
        conn,
        tenant_id=caller.tenant_id,
        revision_id=old["revision_id"],
        decided_by=caller.user_id,
        role="bu_admin",
        decision=body.decision,
        reject_category=body.reject_category,
        note=note,
        batch_id=None,
        overrides=decision_id,
    )
    await repo.set_review_status(conn, old["scan_id"], body.decision)
    await notifications.notify(
        conn,
        tenant_id=caller.tenant_id,
        recipient=old["decided_by"],
        kind="decision_overridden",
        title=f"Your decision on {old['record_no']} was changed",
        body=f"Now {body.decision}",
        object_type="scan",
        object_id=old["scan_id"],
        bu_id=old["bu_id"],
    )
    await notifications.notify(
        conn,
        tenant_id=caller.tenant_id,
        recipient=old["technician_id"],
        kind="scan_approved" if body.decision == "approved" else "scan_rejected",
        title=f"{old['record_no']} was {body.decision}",
        body=_category_text(body.reject_category),
        object_type="scan",
        object_id=old["scan_id"],
        bu_id=old["bu_id"],
    )
    await audit.record(
        conn,
        tenant_id=caller.tenant_id,
        actor_user_id=caller.user_id,
        bu_id=old["bu_id"],
        category="override",
        action="decision.overridden",
        summary=f"Overrode a technician's decision on {old['record_no']}: now {body.decision}",
        object_type="scan",
        object_id=old["scan_id"],
    )
    return Overridden(decision_id=new_id)
