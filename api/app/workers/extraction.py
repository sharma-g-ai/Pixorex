"""AI extraction of a scan (PRD FR-4.4-4.9, contract 2.23; outbox event "extraction.run").

The worker reads the scan's photos from MinIO, sends them through the AI proxy with the
fields of the scan's pinned contract, and stores one ai_field_value per field (insert-only).
Then the attempt is succeeded, failed or timed_out, and the scan moves on:
ready_to_review on success; failed, or retake_required once all 3 attempts are used.

The outbox does not hold a transaction open for the whole AI call (see outbox.Leased): prepare
reads what the call needs while the event is claimed, call reads the photos and asks the
provider with no database connection open, and finish saves the outcome in a second short
transaction, after checking again that the attempt is still queued and the scan still wants it.

Flags (FR-4.7; how each applies is our reading, the PRD only names them):
- missing_required: a required field came back empty;
- critical_not_found: a critical field came back empty;
- no_confidence: a value without a confidence score;
- low_confidence: confidence below the field's flag_below_confidence;
- format_failed: the value doesn't fit the data type (number, date, boolean, dropdown
  choice), or the AI judges it doesn't match the field's format rule (format rules are
  free text, e.g. "UN + 4 digits").
A1 (CONSTITUTION BC-03): prompt, injection defence and attempt budget need human review."""

import asyncio
import re
import time
from dataclasses import dataclass
from datetime import date
from typing import Any
from uuid import UUID

import httpx
import structlog

from app.auth.context import set_context
from app.core import storage
from app.core.db import Conn
from app.repositories import scans as repo
from app.services import ai_proxy
from app.workers.export_files import storage_config
from app.workers.settings import WorkerSettings

_log = structlog.get_logger("pixorex.worker.extraction")
MAX_ATTEMPTS = 3
NUMBER = re.compile(r"[-+]?\d+(?:[.,]\d+)?")
BOOLEANS = {"true": "true", "false": "false", "yes": "true", "no": "false"}


def checked_value(field: dict[str, Any], value: str | None) -> tuple[str | None, bool]:
    """(value to store, fits its data type). Dropdown and boolean values are normalised."""
    if value is None:
        return None, True
    kind = field["data_type"]
    if kind == "number":
        return value, NUMBER.fullmatch(value) is not None
    if kind == "date":
        try:
            date.fromisoformat(value)
        except ValueError:
            return value, False
        return value, True
    if kind == "boolean":
        normal = BOOLEANS.get(value.lower())
        return (normal or value), normal is not None
    if kind == "dropdown":
        choice = next((c for c in field["options"] or [] if c.lower() == value.lower()), None)
        return (choice or value), choice is not None
    return value, True


def flags_for(
    field: dict[str, Any], value: str | None, confidence: float | None, fits: bool
) -> list[str]:
    flags: list[str] = []
    if value is None:
        if field["is_required"]:
            flags.append("missing_required")
        if field["is_critical"]:
            flags.append("critical_not_found")
        return flags
    if confidence is None:
        flags.append("no_confidence")
    elif confidence < field["flag_below"]:
        flags.append("low_confidence")
    if not fits:
        flags.append("format_failed")
    return flags


def ai_config(settings: WorkerSettings) -> ai_proxy.AiConfig | None:
    if not settings.openai_api_key:
        return None
    return ai_proxy.AiConfig(
        url=str(settings.openai_url).rstrip("/"),
        api_key=settings.openai_api_key,
        model=settings.openai_model,
        timeout_s=settings.ai_timeout_s,
    )


def _photo_mime(image: bytes) -> str:
    return "image/png" if image.startswith(b"\x89PNG") else "image/jpeg"


async def _end_without_values(conn: Conn, row: dict[str, Any], status: str) -> None:
    """A failed or timed-out attempt; the scan is failed, or needs a retake after 3."""
    await repo.finish_attempt(conn, row["attempt_id"], status=status)
    if row["review_status"] == "draft" and row["processing_status"] == "extracting":
        done = row["attempt_no"] >= MAX_ATTEMPTS
        await repo.set_processing(conn, row["scan_id"], "retake_required" if done else "failed")


LEASE_MARGIN_S = 30.0  # the lease is the AI timeout plus this: photo reads and two short writes
DEADLINE_MARGIN_S = 10.0  # the whole AI call may take the AI timeout plus this, at most


def lease_s(settings: WorkerSettings) -> float:
    """How long the outbox keeps other workers off the event while the AI call runs."""
    return settings.ai_timeout_s + LEASE_MARGIN_S


@dataclass(frozen=True)
class Job:
    """What the AI call needs, read while the event was claimed."""

    attempt_id: UUID
    attempt_no: int
    type_name: str
    instructions: str | None
    fields: list[dict[str, Any]]
    types: dict[str, UUID]
    photo_keys: list[str]
    config: ai_proxy.AiConfig
    files: storage.StorageConfig
    queue_wait_ms: int | None


@dataclass(frozen=True)
class Outcome:
    """How the AI call ended: succeeded (with the result), failed, or timed_out."""

    status: str
    result: ai_proxy.Extraction | None = None


def _log_timing(job: Job, outcome: str, started: float) -> None:
    """How long the scan waited for the worker and how long the AI call took (FR-4.9).
    Numbers only: nothing from the photos or the values."""
    _log.info(
        "extraction_timing",
        outcome=outcome,
        attempt_no=job.attempt_no,
        queue_wait_ms=job.queue_wait_ms,
        provider_ms=round((time.monotonic() - started) * 1000),
    )

async def prepare(conn: Conn, settings: WorkerSettings, event: dict[str, Any]) -> Job | None:
    """Step 1 of 3, inside the outbox's claim transaction: what the call needs, or None when
    there is nothing to call for."""
    await set_context(conn, tenant_id=event["tenant_id"], is_ea=True)
    row = await repo.attempt_to_run(conn, UUID(event["payload"]["attempt_id"]))
    if row is None:
        return None  # already ran
    if row["review_status"] != "draft" or row["processing_status"] != "extracting":
        await repo.finish_attempt(conn, row["attempt_id"], status="failed")
        return None  # discarded or closed meanwhile: nothing to extract for
    config, files = ai_config(settings), storage_config(settings)
    if config is None or files is None:
        # Retried with backoff by the outbox; after the last try the attempt fails.
        raise LookupError("AI or photo storage is not configured (PIXOREX_OPENAI_*, MINIO_*)")
    return Job(
        attempt_id=row["attempt_id"],
        attempt_no=row["attempt_no"],
        type_name=row["type_name"],
        instructions=row["prompt_instructions"],
        fields=await repo.contract_fields(conn, row["contract_id"]),
        types=await repo.published_types(conn, row["bu_id"]),
        photo_keys=[p["object_key"] for p in await repo.photos(conn, row["scan_id"])],
        config=config,
        files=files,
        queue_wait_ms=event.get("waited_ms"),
    )


async def call(settings: WorkerSettings, job: Job) -> Outcome:
    """Step 2 of 3, with no database connection open: reads the photos and asks the provider.
    A storage error is raised (the outbox retries it); the provider's failures are an outcome."""
    photos = [
        (image, _photo_mime(image))
        for image in [await storage.get(job.files, key) for key in job.photo_keys]
    ]
    started = time.monotonic()
    try:
        async with (
            asyncio.timeout(settings.ai_timeout_s + DEADLINE_MARGIN_S),  # ends before the lease
            httpx.AsyncClient() as http,
        ):
            result = await ai_proxy.extract(
                http,
                job.config,
                photos=photos,
                type_name=job.type_name,
                fields=job.fields,
                type_names=sorted(job.types),
                extra_instructions=job.instructions,
            )
    except TimeoutError:
        outcome = Outcome("timed_out")
    except ai_proxy.AiUnavailableError as exc:
        _log.warning("extraction_failed", reason=str(exc))
        outcome = Outcome("failed")
    else:
        outcome = Outcome("succeeded", result)
    _log_timing(job, outcome.status, started)
    return outcome


async def finish(conn: Conn, event: dict[str, Any], job: Job, outcome: Outcome) -> None:
    """Step 3 of 3, in a second short transaction: locks the attempt again and saves the
    outcome, unless someone else has finished it or the scan no longer wants it."""
    await set_context(conn, tenant_id=event["tenant_id"], is_ea=True)
    row = await repo.attempt_to_run(conn, job.attempt_id)
    if row is None:
        return  # a second worker saved its result first (this lease had run out)
    if row["review_status"] != "draft" or row["processing_status"] != "extracting":
        await repo.finish_attempt(conn, row["attempt_id"], status="failed")
        return  # discarded or closed during the call: nothing to save
    result = outcome.result
    if result is None:
        await _end_without_values(conn, row, outcome.status)
        return
    checked = [
        (field, *checked_value(field, result.fields.get(field["field_key"], {}).get("value")))
        for field in job.fields
    ]
    if job.fields and all(value is None for _, value, _ in checked):
        # Nothing was read at all (a blank screen, a photo of something that isn't a label):
        # a failed attempt, so the technician gets Retry (up to 3 tries) or Retake.
        _log.warning("extraction_nothing_read", attempt_no=job.attempt_no)
        await _end_without_values(conn, row, "failed")
        return
    for field, value, fits in checked:
        item = result.fields.get(field["field_key"], {})
        fits = fits and item.get("format_ok", True)
        confidence = item.get("confidence")
        await repo.save_ai_value(
            conn,
            tenant_id=event["tenant_id"],
            attempt_id=job.attempt_id,
            field_id=field["id"],
            value=value,
            confidence=confidence,
            flags=flags_for(field, value, confidence, fits),
        )
    await repo.finish_attempt(
        conn,
        job.attempt_id,
        status="succeeded",
        detected_label=result.detected_label,
        suggested_type_id=job.types.get(result.suggested_type or ""),
        suggestion_confidence=result.type_confidence,
        tokens_in=result.tokens_in,
        tokens_out=result.tokens_out,
    )
    await repo.set_processing(conn, row["scan_id"], "ready_to_review")


async def give_up(conn: Conn, event: dict[str, Any]) -> None:
    """The outbox stopped retrying (AI or storage not reachable): the attempt fails."""
    await set_context(conn, tenant_id=event["tenant_id"], is_ea=True)
    row = await repo.attempt_to_run(conn, UUID(event["payload"]["attempt_id"]))
    if row is not None:
        await _end_without_values(conn, row, "failed")
