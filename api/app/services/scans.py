"""Capture from the phone (contracts 2.21-2.23, PRD FR-4.1-4.3, FR-6.5).

OPEN (data model): the contract sends photo_count, but V3 has no column for it. Until one is
added, photo numbers are checked against 1-4 and upload-complete needs photos 1..n with no
gap, instead of exactly photo_count photos.
OPEN (PRD open item 9): where the unit's monthly limit is stored, so scans are counted in
quota_usage but never refused with 402 yet.
TODO: the 429 rate limit (100 requests a minute per tenant) is not built for any endpoint."""

import base64
import binascii
import hashlib
from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field

from app.auth import signed_urls
from app.auth.context import Session
from app.core import storage as object_storage
from app.core.problems import ProblemError
from app.core.storage import StorageConfig
from app.repositories import scans as repo

MAX_PHOTO_BYTES = 2 * 1024 * 1024  # 2 MB (Release Plan S2)
JPEG_START = b"\xff\xd8\xff"

ProcessingStatus = Literal[
    "uploading", "extracting", "ready_to_review", "failed", "retake_required"
]
ReviewStatus = Literal[
    "draft", "waiting_for_approval", "approved", "rejected", "closed", "discarded"
]
FlagReason = Literal[
    "low_confidence", "format_failed", "no_confidence", "missing_required", "critical_not_found"
]


class ScanCreate(BaseModel):
    client_capture_id: UUID
    equipment_type_id: UUID
    location_node_id: UUID
    photo_count: int = Field(ge=1, le=4)
    captured_at: AwareDatetime  # with its UTC offset, as the contract's timestamps are
    retake_of_scan_id: UUID | None = None


class Photo(BaseModel):
    photo_no: int
    view_url: str  # signed, valid 15 minutes


class AttemptSummary(BaseModel):
    attempt_no: int
    trigger: Literal["first", "retry", "re_extract"]
    status: Literal["queued", "running", "succeeded", "failed", "timed_out"]
    detected_label: str | None
    suggested_type_id: UUID | None
    suggestion_confidence: float | None


class AiField(BaseModel):
    field_key: str
    label: str
    data_type: Literal["text", "number", "date", "dropdown", "boolean"]
    is_required: bool
    is_critical: bool
    ai_value: str | None
    confidence: float | None  # None = the model gave no score
    flag_reasons: list[FlagReason]


class Scan(BaseModel):
    scan_id: UUID
    record_no: str
    bu_id: UUID
    equipment_type_id: UUID
    equipment_type_name: str
    contract_id: UUID
    location_node_id: UUID
    location_path: str
    processing_status: ProcessingStatus
    review_status: ReviewStatus
    retake_of_scan_id: UUID | None
    photos: list[Photo]
    attempts_used: int
    latest_attempt: AttemptSummary | None
    fields: list[AiField]  # the latest attempt's answers, once it has succeeded
    captured_at: datetime


class UploadConfirmed(BaseModel):
    scan_id: UUID
    record_no: str
    attempt_no: int
    processing_status: ProcessingStatus


async def _view(session: Session, row: dict[str, Any], storage: StorageConfig | None) -> Scan:
    """Photo links are signed only after the caller's access to the scan was checked."""
    photos = await repo.photos(session.conn, row["scan_id"])
    attempts = await repo.attempts(session.conn, row["scan_id"])
    latest = attempts[-1] if attempts else None
    fields = (
        await repo.ai_fields(session.conn, row["contract_id"], latest["id"])
        if latest and latest["status"] == "succeeded"
        else []
    )
    return Scan(
        **{k: row[k] for k in Scan.model_fields if k in row},
        photos=[
            Photo(photo_no=p["photo_no"], view_url=signed_urls.photo_url(storage, p["object_key"]))
            for p in photos
            if storage is not None
        ],
        attempts_used=len(attempts),
        latest_attempt=AttemptSummary(**latest) if latest else None,
        fields=[AiField(**f) for f in fields],
    )


def _require_technician(session: Session, bu_id: UUID) -> None:
    if bu_id not in session.caller.units("field_technician"):
        raise ProblemError(403, "forbidden")


def _same_capture(row: dict[str, Any], session: Session, bu_id: UUID, body: ScanCreate) -> bool:
    return bool(
        row["technician_id"] == session.caller.user_id
        and row["bu_id"] == bu_id
        and row["location_node_id"] == body.location_node_id
        and row["captured_at"] == body.captured_at
        and row["retake_of_scan_id"] == body.retake_of_scan_id
    )


async def create(
    session: Session,
    bu_id: UUID,
    body: ScanCreate,
    idempotency_key: UUID,
    storage: StorageConfig | None,
) -> tuple[Scan, bool]:
    """Contract 2.21. Returns (scan, created): the same capture again returns the first scan."""
    caller = session.caller
    _require_technician(session, bu_id)
    if idempotency_key != body.client_capture_id:
        raise ProblemError(400, "validation", "Idempotency-Key must equal client_capture_id.")
    await repo.lock_capture(session.conn, caller.tenant_id, body.client_capture_id)
    existing = await repo.by_capture_id(session.conn, caller.tenant_id, body.client_capture_id)
    if existing is not None:
        if not _same_capture(existing, session, bu_id, body):
            raise ProblemError(
                409, "idempotency-conflict", "This capture was already sent with other details."
            )
        return await _view(session, existing, storage), False

    kind = await repo.published_type(session.conn, bu_id, body.equipment_type_id)
    if kind is None:
        raise ProblemError(
            409, "type-not-published", "This equipment type isn't published in this unit."
        )
    path = await repo.published_node_path(session.conn, bu_id, body.location_node_id)
    if path is None:
        raise ProblemError(
            409, "location-not-published", "This location isn't in the unit's published tree."
        )
    if body.retake_of_scan_id is not None:
        original = await repo.scan_for_update(session.conn, body.retake_of_scan_id)
        if original is None or original["technician_id"] != caller.user_id:
            raise ProblemError(409, "invalid-state", "Only your own scan can be retaken.")
        # Status table: rejected, or a draft whose extraction ended in retake_required.
        retakeable = original["review_status"] == "rejected" or (
            original["review_status"] == "draft"
            and original["processing_status"] == "retake_required"
        )
        if not retakeable:
            raise ProblemError(409, "invalid-state", "This scan can't be retaken now.")
        await repo.close(session.conn, original["scan_id"])

    scan_id = await repo.insert(
        session.conn,
        tenant_id=caller.tenant_id,
        bu_id=bu_id,
        process_id=kind["process_id"],
        record_no=await repo.next_record_no(session.conn, caller.tenant_id),
        client_capture_id=body.client_capture_id,
        technician_id=caller.user_id,
        equipment_type_id=body.equipment_type_id,
        contract_id=kind["contract_id"],
        location_node_id=body.location_node_id,
        location_path=path,
        retake_of_scan_id=body.retake_of_scan_id,
        captured_at=body.captured_at,
    )
    await repo.count_quota(session.conn, caller.tenant_id, bu_id)
    row = await repo.scan(session.conn, scan_id)
    if row is None:
        raise RuntimeError("the new scan is not visible")
    return await _view(session, row, storage), True


async def _own_scan(session: Session, scan_id: UUID) -> dict[str, Any]:
    """The caller's own scan, locked; 404 if they can't see it, 403 if it isn't theirs."""
    row = await repo.scan_for_update(session.conn, scan_id)
    if row is None:
        raise ProblemError(404, "not-found")
    if row["technician_id"] != session.caller.user_id:
        raise ProblemError(403, "forbidden")
    _require_technician(session, row["bu_id"])
    return row


def _digest(header: str) -> bytes:
    """The SHA-256 from a Content-Digest header (RFC 9530): sha-256=:<base64>:"""
    for part in header.split(","):
        name, _, value = part.strip().partition("=")
        if name.strip().lower() == "sha-256" and value.startswith(":") and value.endswith(":"):
            try:
                return base64.b64decode(value[1:-1], validate=True)
            except (binascii.Error, ValueError):
                break
    raise ProblemError(
        400, "validation", "Content-Digest must carry the photo's SHA-256: sha-256=:<base64>:"
    )


async def upload_photo(
    session: Session,
    scan_id: UUID,
    photo_no: int,
    body: bytes,
    content_digest: str,
    storage: StorageConfig | None,
) -> None:
    """Contract 2.22: stored at /{tenant}/{bu}/{scan}/{photo_no}; only the key and SHA-256 are
    kept. The same photo number again replaces it while the scan is uploading."""
    row = await _own_scan(session, scan_id)
    if row["processing_status"] != "uploading":
        raise ProblemError(409, "invalid-state", "Photos can only be sent while uploading.")
    if len(body) > MAX_PHOTO_BYTES:
        raise ProblemError(400, "photo-too-large", "A photo can be at most 2 MB.")
    if not body.startswith(JPEG_START):
        raise ProblemError(400, "validation", "The photo must be a JPEG.")
    digest = hashlib.sha256(body).digest()
    if digest != _digest(content_digest):
        raise ProblemError(400, "digest-mismatch", "The photo doesn't match its Content-Digest.")
    if storage is None:
        raise ProblemError(503, "service-unavailable", "Photo storage isn't available.")
    key = f"{row['tenant_id']}/{row['bu_id']}/{scan_id}/{photo_no}"
    await object_storage.put(storage, key, body, "image/jpeg")
    await repo.save_photo(
        session.conn,
        tenant_id=row["tenant_id"],
        scan_id=scan_id,
        photo_no=photo_no,
        object_key=key,
        sha256=digest.hex(),
    )


async def confirm_upload(session: Session, scan_id: UUID) -> UploadConfirmed:
    """Contract 2.23: queues attempt 1 for the AI proxy. Safe to retry: while attempt 1 is
    still waiting or running, the same answer comes back."""
    row = await _own_scan(session, scan_id)
    attempts = await repo.attempts(session.conn, scan_id)
    if row["processing_status"] == "extracting" and len(attempts) == 1:
        return UploadConfirmed(
            scan_id=scan_id,
            record_no=row["record_no"],
            attempt_no=1,
            processing_status="extracting",
        )
    if row["processing_status"] != "uploading" or attempts:
        raise ProblemError(409, "invalid-state", "This scan's upload was already confirmed.")
    numbers = [p["photo_no"] for p in await repo.photos(session.conn, scan_id)]
    if not numbers or numbers != list(range(1, len(numbers) + 1)):
        raise ProblemError(409, "photos-missing", "Send every photo before confirming.")
    await repo.start_attempt(
        session.conn,
        tenant_id=row["tenant_id"],
        scan_id=scan_id,
        attempt_no=1,
        contract_id=row["contract_id"],
        trigger="first",
    )
    return UploadConfirmed(
        scan_id=scan_id, record_no=row["record_no"], attempt_no=1, processing_status="extracting"
    )


async def get(session: Session, scan_id: UUID, storage: StorageConfig | None) -> Scan:
    """Contract 2.24: the technician who took it, admins of the unit, or the technician it is
    assigned to for review."""
    caller = session.caller
    row = await repo.scan(session.conn, scan_id)
    if row is None:
        raise ProblemError(404, "not-found")
    allowed = (
        row["technician_id"] == caller.user_id
        or caller.is_ea
        or row["bu_id"] in caller.units("bu_admin")
        or await repo.open_assignee(session.conn, scan_id) == caller.user_id
    )
    if not allowed:
        raise ProblemError(403, "forbidden")
    return await _view(session, row, storage)


MAX_ATTEMPTS = 3  # per scan across retries and re-extracts, then retake only (FR-4)


class ReExtract(BaseModel):
    equipment_type_id: UUID


async def _next_attempt(session: Session, row: dict[str, Any], allowed_from: str) -> int:
    """The next attempt number, after the state checks every new attempt shares."""
    if row["review_status"] != "draft" or row["processing_status"] != allowed_from:
        raise ProblemError(409, "invalid-state", "This scan can't be extracted again now.")
    used = len(await repo.attempts(session.conn, row["scan_id"]))
    if used >= MAX_ATTEMPTS:
        raise ProblemError(
            409, "scan-attempts-used", "All 3 extraction attempts are used. Retake the photos."
        )
    return used + 1


async def _queued(session: Session, scan_id: UUID, attempt_no: int) -> AttemptSummary:
    attempts = await repo.attempts(session.conn, scan_id)
    return AttemptSummary(**next(a for a in attempts if a["attempt_no"] == attempt_no))


async def retry(session: Session, scan_id: UUID) -> AttemptSummary:
    """Contract 2.25: only after a failed extraction; the same contract again."""
    row = await _own_scan(session, scan_id)
    attempt_no = await _next_attempt(session, row, "failed")
    await repo.start_attempt(
        session.conn,
        tenant_id=row["tenant_id"],
        scan_id=scan_id,
        attempt_no=attempt_no,
        contract_id=row["contract_id"],
        trigger="retry",
    )
    return await _queued(session, scan_id, attempt_no)


async def re_extract(session: Session, scan_id: UUID, body: ReExtract) -> AttemptSummary:
    """Contract 2.26, the type mismatch path: the scan takes the other type's active contract."""
    row = await _own_scan(session, scan_id)
    attempt_no = await _next_attempt(session, row, "ready_to_review")
    kind = await repo.published_type(session.conn, row["bu_id"], body.equipment_type_id)
    if kind is None:
        raise ProblemError(
            409, "type-not-published", "This equipment type isn't published in this unit."
        )
    await repo.set_type(session.conn, scan_id, body.equipment_type_id, kind["contract_id"])
    await repo.start_attempt(
        session.conn,
        tenant_id=row["tenant_id"],
        scan_id=scan_id,
        attempt_no=attempt_no,
        contract_id=kind["contract_id"],
        trigger="re_extract",
    )
    return await _queued(session, scan_id, attempt_no)


async def discard(session: Session, scan_id: UUID) -> None:
    """Contract 2.27: only before it is submitted for review."""
    row = await _own_scan(session, scan_id)
    if row["review_status"] != "draft":
        raise ProblemError(409, "invalid-state", "Only a scan not yet submitted can be discarded.")
    await repo.discard(session.conn, scan_id)
