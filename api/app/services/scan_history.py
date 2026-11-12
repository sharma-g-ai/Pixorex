"""Contract 3.28: what happened to a scan and where it is now, built from the scan's own
tables (attempts, revisions, decisions, retake links), not from the audit log text. The phone
and the web dashboard both read this, so they show the same events and times."""

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel

from app.auth.context import Session
from app.repositories import scans as repo
from app.services import scans

EventKind = Literal[
    "captured",
    "read",
    "read_failed",
    "submitted",
    "resubmitted",
    "rejected",
    "approved",
    "decision_changed",
    "replaces",
    "replaced_by",
]

CATEGORY = {
    "image_unclear": "Image unclear",
    "data_correction_needed": "Data correction needed",
    "wrong_equipment_type": "Wrong equipment type",
    "other": "Other",
}


class HistoryEvent(BaseModel):
    kind: EventKind
    at: datetime
    title: str  # "Rejected by Bo Plant04", or "Rejected by you" for the caller's own
    detail: str | None  # the note, the changed values, the place


class Now(BaseModel):
    text: str  # "With Bo Plant04 for review"
    since: datetime | None
    needs_technician: bool  # the technician who captured it has something to do


class ScanHistory(BaseModel):
    scan_id: UUID
    record_no: str
    events: list[HistoryEvent]  # oldest first
    now: Now


def _who(name: str, user_id: UUID, me: UUID, *, you: str = "you") -> str:
    return you if user_id == me else name


def _changed(old: dict[str, Any], new: dict[str, Any], labels: dict[str, str]) -> str | None:
    parts = []
    for key, value in new.items():
        before = old.get(key)
        if before != value:
            parts.append(f"{labels.get(key, key)}: {before or '—'} → {value or '—'}")
    return " · ".join(parts) or None


async def get(session: Session, scan_id: UUID) -> ScanHistory:
    row = await scans.visible_scan(session, scan_id)
    conn, me = session.conn, session.caller.user_id
    owner = row["technician_id"]
    attempts = await repo.history_attempts(conn, scan_id)
    revisions = await repo.history_revisions(conn, scan_id)
    decisions = await repo.history_decisions(conn, scan_id)
    labels = await repo.field_labels(conn, row["contract_id"])
    related = await repo.related_scans(conn, scan_id, row["retake_of_scan_id"])
    holder = await repo.holder(conn, scan_id, owner)

    events: list[HistoryEvent] = []
    captured_by = await _name(session, owner)
    events.append(
        HistoryEvent(
            kind="captured",
            at=row["captured_at"],
            title=f"Scanned by {_who(captured_by, owner, me)}",
            detail=f"{row['equipment_type_name']} · {row['location_path']}",
        )
    )
    if related["replaces"]:
        events.append(
            HistoryEvent(
                kind="replaces",
                at=row["captured_at"],
                title="Retake of an earlier scan",
                detail=f"Replaces scan {related['replaces']['record_no']}",
            )
        )
    for a in attempts:
        ok = a["status"] == "succeeded"
        if a["status"] in ("succeeded", "failed", "timed_out"):
            events.append(
                HistoryEvent(
                    kind="read" if ok else "read_failed",
                    at=a["updated_at"],
                    title="Label read" if ok else "Couldn't read the label",
                    detail=f"Try {a['attempt_no']} of {scans.MAX_ATTEMPTS}",
                )
            )
    previous: dict[str, Any] = {}
    for r in revisions:
        fixed = r["origin"] == "rejection_fix"
        by = _who(r["by_name"], r["submitted_by"], me)
        parts = []
        if r["corrected"]:
            parts.append(f"{r['corrected']} corrected")
        if r["unreadable"]:
            parts.append(f"{r['unreadable']} marked unreadable")
        checked = " · ".join(parts) or "nothing changed"
        events.append(
            HistoryEvent(
                kind="resubmitted" if fixed else "submitted",
                at=r["submitted_at"],
                title=f"{'Fixed and sent back' if fixed else 'Submitted for review'} by {by}",
                detail=(_changed(previous, r["values_json"], labels) if fixed else checked),
            )
        )
        previous = r["values_json"]
    by_id = {d["id"]: d for d in decisions}
    for d in decisions:
        by = _who(d["by_name"], d["decided_by"], me)
        overrode = by_id.get(d["overrides_decision_id"]) if d["overrides_decision_id"] else None
        verdict = "Approved" if d["decision"] == "approved" else "Rejected"
        reason = CATEGORY.get(d["reject_category"] or "", None)
        detail = " · ".join(x for x in (reason, f"“{d['note']}”" if d["note"] else None) if x)
        events.append(
            HistoryEvent(
                kind="decision_changed" if overrode else d["decision"],
                at=d["decided_at"],
                title=(
                    f"{'You' if by == 'you' else by} changed the decision to {verdict.lower()}"
                    if overrode
                    else f"{verdict} by {by}"
                ),
                detail=detail or None,
            )
        )
    if related["replaced_by"]:
        events.append(
            HistoryEvent(
                kind="replaced_by",
                at=related["replaced_by"]["captured_at"],
                title="Closed: retaken as a new scan",
                detail=f"Replaced by scan {related['replaced_by']['record_no']}",
            )
        )
    events.sort(key=lambda e: e.at)
    return ScanHistory(
        scan_id=scan_id,
        record_no=row["record_no"],
        events=events,
        now=_now(row, attempts, revisions, decisions, holder, events),
    )


async def _name(session: Session, user_id: UUID) -> str:
    return await repo.full_name(session.conn, user_id) or "someone"


def _now(
    row: dict[str, Any],
    attempts: list[dict[str, Any]],
    revisions: list[dict[str, Any]],
    decisions: list[dict[str, Any]],
    holder: dict[str, Any] | None,
    events: list[HistoryEvent],
) -> Now:
    """One line for where the scan is, and whether the technician has to act."""
    processing, review = row["processing_status"], row["review_status"]
    last_at = events[-1].at if events else None
    if review == "approved":
        return Now(text="Approved. Nothing more to do.", since=last_at, needs_technician=False)
    if review == "closed":
        return Now(text="Closed: replaced by a new scan.", since=last_at, needs_technician=False)
    if review == "discarded":
        return Now(text="Discarded.", since=last_at, needs_technician=False)
    if review == "rejected":
        who = next(
            (d["by_name"] for d in reversed(decisions) if d["decision"] == "rejected"),
            "the reviewer",
        )
        return Now(
            text=f"Sent back by {who}. Fix the fields or retake the photo.",
            since=last_at,
            needs_technician=True,
        )
    if review == "waiting_for_approval":
        who = holder["full_name"] if holder else "the reviewer"
        return Now(
            text=f"With {who} for review.",
            since=revisions[-1]["submitted_at"] if revisions else last_at,
            needs_technician=False,
        )
    if processing == "uploading":
        return Now(text="Uploading the photos.", since=row["captured_at"], needs_technician=False)
    if processing == "extracting":
        since = attempts[-1]["created_at"] if attempts else row["captured_at"]
        return Now(text="The label is being read by the AI.", since=since, needs_technician=False)
    if processing == "ready_to_review":
        return Now(
            text="Waiting for you to check what was read.", since=last_at, needs_technician=True
        )
    if processing == "retake_required":
        return Now(
            text=f"All {scans.MAX_ATTEMPTS} reads failed. Retake the photo.",
            since=last_at,
            needs_technician=True,
        )
    return Now(
        text="The label couldn't be read. Retry or retake the photo.",
        since=last_at,
        needs_technician=True,
    )
