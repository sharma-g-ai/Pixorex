"""AI extraction of a scan (PRD FR-4.4-4.9, contract 2.23; outbox event "extraction.run").

The worker reads the scan's photos from MinIO, sends them through the AI proxy with the
fields of the scan's pinned contract, and stores one ai_field_value per field (insert-only).
Then the attempt is succeeded, failed or timed_out, and the scan moves on:
ready_to_review on success; failed, or retake_required once all 3 attempts are used.

Flags (FR-4.7; how each applies is our reading, the PRD only names them):
- missing_required: a required field came back empty;
- critical_not_found: a critical field came back empty;
- no_confidence: a value without a confidence score;
- low_confidence: confidence below the field's flag_below_confidence;
- format_failed: the value doesn't fit the data type (number, date, boolean, dropdown
  choice), or the AI judges it doesn't match the field's format rule (format rules are
  free text, e.g. "UN + 4 digits").
A1 (CONSTITUTION BC-03): prompt, injection defence and attempt budget need human review."""

import re
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
    if not settings.portkey_api_key or not settings.portkey_config_id:
        return None
    return ai_proxy.AiConfig(
        url=str(settings.portkey_url).rstrip("/"),
        api_key=settings.portkey_api_key,
        config_id=settings.portkey_config_id,
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


async def run(conn: Conn, settings: WorkerSettings, event: dict[str, Any], _send: Any) -> None:
    await set_context(conn, tenant_id=event["tenant_id"], is_ea=True)
    row = await repo.attempt_to_run(conn, UUID(event["payload"]["attempt_id"]))
    if row is None:
        return  # already ran
    if row["review_status"] != "draft" or row["processing_status"] != "extracting":
        await repo.finish_attempt(conn, row["attempt_id"], status="failed")
        return  # discarded or closed meanwhile: nothing to extract for
    config, files = ai_config(settings), storage_config(settings)
    if config is None or files is None:
        # Retried with backoff by the outbox; after the last try the attempt fails.
        raise LookupError("AI or photo storage is not configured (PIXOREX_PORTKEY_*, MINIO_*)")
    photos = [
        (image, _photo_mime(image))
        for image in [
            await storage.get(files, p["object_key"])
            for p in await repo.photos(conn, row["scan_id"])
        ]
    ]
    fields = await repo.contract_fields(conn, row["contract_id"])
    types = await repo.published_types(conn, row["bu_id"])
    try:
        async with httpx.AsyncClient() as http:
            result = await ai_proxy.extract(
                http,
                config,
                photos=photos,
                type_name=row["type_name"],
                fields=fields,
                type_names=sorted(types),
                extra_instructions=row["prompt_instructions"],
            )
    except TimeoutError:
        await _end_without_values(conn, row, "timed_out")
        return
    except ai_proxy.AiUnavailableError as exc:
        _log.warning("extraction_failed", reason=str(exc))
        await _end_without_values(conn, row, "failed")
        return
    for field in fields:
        item = result.fields.get(field["field_key"], {})
        value, fits = checked_value(field, item.get("value"))
        fits = fits and item.get("format_ok", True)
        confidence = item.get("confidence")
        await repo.save_ai_value(
            conn,
            tenant_id=event["tenant_id"],
            attempt_id=row["attempt_id"],
            field_id=field["id"],
            value=value,
            confidence=confidence,
            flags=flags_for(field, value, confidence, fits),
        )
    await repo.finish_attempt(
        conn,
        row["attempt_id"],
        status="succeeded",
        detected_label=result.detected_label,
        suggested_type_id=types.get(result.suggested_type or ""),
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
