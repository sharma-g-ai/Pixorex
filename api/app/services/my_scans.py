"""A technician's own scans (contracts 3.1, 3.2; PRD FR-5.1, screens T 47-61, 69-70, 80).

Self-review rules, from the contract and the screens (T 57-61): every field the AI flagged
needs a verdict (keep, fix or mark unreadable). A required field is empty when it ends with
no value and is not marked unreadable; it is refused unless the phone sends submit_anyway,
then it is kept as left_empty and listed in empty_required_fields."""

from datetime import date, datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.auth.context import Session
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.repositories import audit
from app.repositories import scans as repo

Verdict = Literal["accepted", "corrected", "unreadable", "left_empty"]
UnreadableReason = Literal["label_worn", "not_on_nameplate", "covered_or_unreachable", "other"]


class MyScan(BaseModel):
    scan_id: UUID
    record_no: str
    equipment_type_name: str
    location_path: str
    processing_status: str
    review_status: str
    attempts_used: int
    reject_category: str | None
    updated_at: datetime


class MyScanPage(BaseModel):
    items: list[MyScan]
    page: PageInfo


class FieldVerdict(BaseModel):
    field_key: str
    verification_state: Verdict
    value: str | None = None  # required for corrected
    unreadable_reason: UnreadableReason | None = None  # required for unreadable
    note: str | None = Field(default=None, max_length=2000)  # required for reason other


class RevisionInput(BaseModel):
    fields: list[FieldVerdict]
    submit_anyway: bool = False


class Revision(BaseModel):
    revision_id: UUID
    revision_no: int
    origin: Literal["technician_review", "rejection_fix"]
    empty_required_fields: list[str]
    review_status: str


def _require_technician(session: Session) -> None:
    if not session.caller.units("field_technician"):
        raise ProblemError(403, "forbidden")


async def list_mine(
    session: Session,
    *,
    tab: str | None,
    bu_id: UUID | None,
    review_status: str | None,
    equipment_type_id: UUID | None,
    from_: date | None,
    to: date | None,
    q: str | None,
    cursor: str | None,
    limit: int,
) -> MyScanPage:
    """Contract 3.1. The phone's offline queue is not here: it lives only on the phone."""
    _require_technician(session)
    if from_ and to and from_ > to:
        raise ProblemError(400, "validation", "'from' must not be after 'to'.")
    rows = await repo.my_scans(
        session.conn,
        technician_id=session.caller.user_id,
        filters={
            "tab": tab,
            "bu_id": bu_id,
            "review_status": review_status,
            "equipment_type_id": equipment_type_id,
            "from": from_,
            "to": to,
            "q": (q or "").strip(),
        },
        after=decode_cursor(cursor, 2),
        limit=limit,
    )
    more = len(rows) > limit
    rows = rows[:limit]
    return MyScanPage(
        items=[MyScan(**r) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["updated_at"].isoformat(), rows[-1]["scan_id"])
            if more
            else None
        ),
    )


def _check_verdict(v: FieldVerdict) -> None:
    """The per-field rules of contract 3.2 (400 when broken)."""
    if v.verification_state == "corrected" and not (v.value or "").strip():
        raise ProblemError(400, "validation", f"{v.field_key}: a fix needs the corrected value.")
    if (v.verification_state == "unreadable") != (v.unreadable_reason is not None):
        raise ProblemError(
            400, "validation", f"{v.field_key}: a reason goes with unreadable, and only with it."
        )
    if v.unreadable_reason == "other" and not (v.note or "").strip():
        raise ProblemError(400, "validation", f"{v.field_key}: reason 'other' needs a note.")


async def submit(session: Session, scan_id: UUID, body: RevisionInput) -> Revision:
    """Contract 3.2: self-review, or fix and resubmit after a rejection."""
    caller = session.caller
    row = await repo.scan_for_update(session.conn, scan_id)
    if row is None:
        raise ProblemError(404, "not-found")
    if row["technician_id"] != caller.user_id:
        raise ProblemError(403, "forbidden")
    if row["bu_id"] not in caller.units("field_technician"):
        raise ProblemError(403, "forbidden")
    self_review = row["review_status"] == "draft" and row["processing_status"] == "ready_to_review"
    fixing = row["review_status"] == "rejected"
    if not (self_review or fixing):
        raise ProblemError(409, "invalid-state", "This scan can't be submitted now.")

    attempts = [a for a in await repo.attempts(session.conn, scan_id) if a["status"] == "succeeded"]
    known = (
        {
            f["field_key"]: f
            for f in await repo.ai_fields(session.conn, row["contract_id"], attempts[-1]["id"])
        }
        if attempts
        else {}
    )
    given: dict[str, FieldVerdict] = {}
    for v in body.fields:
        if v.field_key not in known:
            raise ProblemError(400, "validation", f"{v.field_key} isn't a field of this scan.")
        if v.field_key in given:
            raise ProblemError(400, "validation", f"{v.field_key} is sent twice.")
        _check_verdict(v)
        given[v.field_key] = v
    unchecked = [f["label"] for k, f in known.items() if f["flag_reasons"] and k not in given]
    if unchecked:
        raise ProblemError(
            409,
            "flags-not-reviewed",
            "Check every flagged field first: " + ", ".join(unchecked) + ".",
            fields=unchecked,
        )

    rows: list[dict[str, Any]] = []
    values: dict[str, str | None] = {}
    empty: list[str] = []
    for key, f in known.items():
        v = given.get(key) or FieldVerdict(
            field_key=key, verification_state="accepted" if f["ai_value"] else "left_empty"
        )
        value = {
            "accepted": f["ai_value"],
            "corrected": (v.value or "").strip(),
        }.get(v.verification_state)
        state = v.verification_state
        if state == "accepted" and not value:
            state = "left_empty"  # keeping an empty AI answer leaves the field empty
        if f["is_required"] and state == "left_empty":
            empty.append(key)
        values[key] = value
        rows.append(
            {
                "ai_field_value_id": f["ai_field_value_id"],
                "field_key": key,
                "value": value,
                "verification_state": state,
                "unreadable_reason": v.unreadable_reason,
                "note": (v.note or "").strip() or None,
            }
        )
    if empty and not body.submit_anyway:
        labels = [known[k]["label"] for k in empty]
        raise ProblemError(
            409,
            "required-fields-empty",
            "Required fields are empty: " + ", ".join(labels) + ".",
            fields=labels,
        )

    revision = await repo.add_revision(
        session.conn,
        tenant_id=caller.tenant_id,
        scan_id=scan_id,
        origin="rejection_fix" if fixing else "technician_review",
        values=values,
        empty_required=empty,
        submitted_by=caller.user_id,
        resubmit_to=await repo.rejected_by(session.conn, scan_id) if fixing else None,
        fields=rows,
    )
    await audit.record(
        session.conn,
        tenant_id=caller.tenant_id,
        actor_user_id=caller.user_id,
        bu_id=row["bu_id"],
        category="review",
        action="scan.resubmitted" if fixing else "scan.submitted",
        summary=f"{'Resubmitted' if fixing else 'Submitted'} {row['record_no']} for review",
        object_type="scan",
        object_id=scan_id,
    )
    return Revision(**revision, review_status="waiting_for_approval")
