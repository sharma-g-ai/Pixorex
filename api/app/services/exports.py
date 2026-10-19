"""CSV exports (contracts 4.1, 4.2, PRD FR-6.4, decision D-06).

Up to 1,000 rows the CSV comes back in the request. Larger exports become a queued job: the
worker builds the file into private storage (MinIO) and the requester gets a signed link
that works for 1 hour.
TODO (A0, BC-09, OPEN O-14): the DLP scan before delivery, and photo links, are not built."""

import csv
import io
from datetime import UTC, date, datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.auth import signed_urls
from app.auth.context import Session
from app.core.db import Conn
from app.core.problems import ProblemError
from app.core.storage import StorageConfig
from app.repositories import audit
from app.repositories import exports as repo

DIRECT_LIMIT = 1000
Column = Literal["field_values", "ai_vs_technician", "review_decision"]


class ExportFilters(BaseModel):
    model_config = {"populate_by_name": True}

    bu_id: UUID | None = None
    review_status: str | None = None
    equipment_type_id: UUID | None = None
    from_: date | None = Field(default=None, alias="from")
    to: date | None = None
    category: str | None = None


class ExportOptions(BaseModel):
    columns: list[Column] = Field(default_factory=list)
    include_photo_links: bool = False


class ExportInput(BaseModel):
    export_kind: Literal["scans", "audit_log"]
    filters: ExportFilters = Field(default_factory=ExportFilters)
    options: ExportOptions = Field(default_factory=ExportOptions)


class ExportJob(BaseModel):
    export_id: UUID
    export_kind: Literal["scans", "audit_log"]
    status: Literal["queued", "ready", "failed"]
    row_count: int | None
    download_url: str | None = None
    link_expires_at: datetime | None


def _scope(session: Session, filters: ExportFilters) -> list[UUID] | None:
    """The EA exports any unit; a BU Admin only the units they run (D-06)."""
    caller = session.caller
    if caller.is_ea:
        return None
    caller.require_admin()
    units = sorted(caller.units("bu_admin"))
    if filters.bu_id is not None and filters.bu_id not in units:
        raise ProblemError(403, "forbidden")
    return units


def _cell(value: Any) -> str:
    """Spreadsheet-safe text: a leading = + - @ (or tab/CR) would run as a formula."""
    if value is None:
        return ""
    text = value.isoformat() if isinstance(value, datetime | date) else str(value)
    return "'" + text if text[:1] in ("=", "+", "-", "@", "\t", "\r") else text


def _csv(header: list[str], rows: list[list[Any]]) -> str:
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\r\n")
    writer.writerow(header)
    writer.writerows([[_cell(v) for v in row] for row in rows])
    return out.getvalue()


async def scans_csv(
    conn: Conn,
    units: list[UUID] | None,
    filters: dict[str, Any],
    columns: list[Column],
    limit: int | None = DIRECT_LIMIT,
) -> tuple[str, int]:
    """The CSV and its row count. limit None: every matching row (built files)."""
    rows = await repo.scans(conn, units, filters, limit)
    keys = sorted({k for r in rows for k in (r["values_json"] or {})})
    ai = (
        await repo.ai_values(conn, [r["id"] for r in rows]) if "ai_vs_technician" in columns else {}
    )
    header = [
        "Record no",
        "Unit",
        "Location",
        "Equipment type",
        "Captured by",
        "Captured at",
        "Review status",
    ]
    if "field_values" in columns or "ai_vs_technician" in columns:
        for key in keys:
            header.append(key)
            if "ai_vs_technician" in columns:
                header += [f"{key} (AI)", f"{key} (AI confidence)"]
    if "review_decision" in columns:
        header += ["Decision", "Reject category", "Decided by", "Decided at"]
    lines = []
    for r in rows:
        line = [
            r["record_no"],
            r["unit"],
            r["location"],
            r["equipment_type"],
            r["captured_by"],
            r["captured_at"],
            r["review_status"],
        ]
        if "field_values" in columns or "ai_vs_technician" in columns:
            for key in keys:
                line.append((r["values_json"] or {}).get(key))
                if "ai_vs_technician" in columns:
                    found = ai.get(r["id"], {}).get(key, {})
                    line += [found.get("value"), found.get("confidence")]
        if "review_decision" in columns:
            line += [r["decision"], r["reject_category"], r["decided_by"], r["decided_at"]]
        lines.append(line)
    return _csv(header, lines), len(rows)


async def audit_csv(
    conn: Conn,
    units: list[UUID] | None,
    filters: dict[str, Any],
    limit: int | None = DIRECT_LIMIT,
) -> tuple[str, int]:
    rows = await repo.audit(conn, units, filters, limit)
    header = ["When", "Who", "Unit", "Category", "Summary", "Action", "Object"]
    text = _csv(
        header,
        [
            [
                r["occurred_at"],
                r["who"] or "System",
                r["unit"],
                r["category"],
                r["summary"],
                r["action"],
                f"{r['object_type'] or ''} {r['object_id'] or ''}".strip(),
            ]
            for r in rows
        ],
    )
    return text, len(rows)


async def create(session: Session, body: ExportInput) -> tuple[str | None, ExportJob | None]:
    """Returns (csv, None) for up to 1,000 rows, or (None, queued job) for more."""
    caller = session.caller
    units = _scope(session, body.filters)
    if body.filters.from_ and body.filters.to and body.filters.from_ > body.filters.to:
        raise ProblemError(400, "validation", "'from' must not be after 'to'.")
    filters = body.filters.model_dump(by_alias=True, exclude_none=True)
    if body.export_kind == "scans":
        count = await repo.count_scans(session.conn, units, filters)
    else:
        count = await repo.count_audit(session.conn, units, filters)
    job: ExportJob | None = None
    csv_text: str | None = None
    # A BU Admin's export belongs to their unit (D-06): the job, and its audit row, carry it
    # so they can see both under RLS.
    own_unit = body.filters.bu_id or (units[0] if units else None)
    if count > DIRECT_LIMIT:
        row = await repo.create_job(
            session.conn,
            tenant_id=caller.tenant_id,
            bu_id=own_unit,
            user_id=caller.user_id,
            kind=body.export_kind,
            filters=filters,
            options=body.options.model_dump(),
            row_count=count,
        )
        job = ExportJob(**row)
    elif body.export_kind == "scans":
        csv_text, _ = await scans_csv(session.conn, units, filters, body.options.columns)
    else:
        csv_text, _ = await audit_csv(session.conn, units, filters)
    noun = "scans" if body.export_kind == "scans" else "audit log entries"
    await audit.record(
        session.conn,
        tenant_id=caller.tenant_id,
        actor_user_id=caller.user_id,
        bu_id=own_unit,
        category="export",
        action="export.queued" if job else "export.downloaded",
        summary=f"Exported {count} {noun} to CSV" + (" (queued)" if job else ""),
        object_type="export_job" if job else None,
        object_id=job.export_id if job else None,
    )
    return csv_text, job


def file_name(kind: str) -> str:
    return f"pixorex-{kind.replace('_', '-')}.csv"


async def get(session: Session, export_id: UUID, storage: StorageConfig | None) -> ExportJob:
    """Contract 4.2: the requester only; a ready link works for 1 hour (409 link-expired)."""
    session.caller.require_admin()
    row = await repo.job(session.conn, export_id)
    if row is None or row["requested_by"] != session.caller.user_id:
        raise ProblemError(404, "not-found")
    if (
        row["status"] == "ready"
        and row["link_expires_at"]
        and row["link_expires_at"] < datetime.now(UTC)
    ):
        raise ProblemError(409, "link-expired", "The download link has expired. Export again.")
    job = ExportJob(**row)
    if row["status"] == "ready" and storage is not None:
        # Authorization was checked above, on this request (BC-09).
        job.download_url = signed_urls.export_download_url(
            storage, row["file_key"], row["link_expires_at"], file_name(row["export_kind"])
        )
    return job
