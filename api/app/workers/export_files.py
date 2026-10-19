"""Builds export files over 1,000 rows (contract 4.1, PRD FR-6.4, D-06).

The requester's rights are checked again at build time: a BU Admin removed from a unit in
the meantime gets only the units they still run, or a failed job.
TODO (A0, BC-09, OPEN O-14): the DLP scan before delivery is not built."""

from typing import Any
from uuid import UUID

from app.auth.context import set_context
from app.core import storage
from app.core.db import Conn
from app.repositories import exports as repo
from app.repositories.notifications import notify
from app.services import exports
from app.workers.settings import WorkerSettings


def storage_config(settings: WorkerSettings) -> storage.StorageConfig | None:
    return storage.config_from(
        minio_url=settings.minio_url,
        minio_public_url=None,
        access_key=settings.minio_access_key,
        secret_key=settings.minio_secret_key,
        bucket=settings.minio_bucket,
    )


def _scope(roles: list[dict[str, Any]], filters: dict[str, Any]) -> tuple[bool, list[UUID] | None]:
    """(allowed, units): units None means every unit (EA), else the units they run now."""
    if any(r["role"] == "enterprise_admin" for r in roles):
        return True, None
    units = sorted(r["bu_id"] for r in roles if r["role"] == "bu_admin" and r["bu_id"])
    wanted = filters.get("bu_id")
    return bool(units) and not (wanted and UUID(str(wanted)) not in units), units


async def build(conn: Conn, settings: WorkerSettings, event: dict[str, Any], _send: Any) -> None:
    export_id = UUID(event["payload"]["export_id"])
    await set_context(conn, tenant_id=event["tenant_id"], is_ea=True)
    job = await repo.job_to_build(conn, export_id)
    if job is None:
        return  # already built or failed
    allowed, scope = _scope(await repo.roles_of(conn, job["requested_by"]), job["filters_json"])
    if not allowed or job["requester_status"] == "removed":
        await repo.mark_failed(conn, export_id)
        return
    config = storage_config(settings)
    if config is None:
        raise LookupError("storage is not configured (PIXOREX_MINIO_*)")
    filters = job["filters_json"]
    if job["export_kind"] == "scans":
        columns = job["options_json"].get("columns", [])
        text, rows = await exports.scans_csv(conn, scope, filters, columns, limit=None)
    else:
        text, rows = await exports.audit_csv(conn, scope, filters, limit=None)
    key = f"exports/{job['tenant_id']}/{export_id}.csv"
    await storage.ensure_bucket(config)
    await storage.put(config, key, text.encode("utf-8"), "text/csv; charset=utf-8")
    await repo.mark_ready(conn, export_id, key, rows)
    await notify(
        conn,
        tenant_id=job["tenant_id"],
        recipient=job["requested_by"],
        bu_id=job["bu_id"],
        kind="export_ready",
        title="Your CSV export is ready",
        body=f"{rows} rows. The download link works for 1 hour.",
        object_type="export_job",
        object_id=export_id,
    )


async def give_up(conn: Conn, event: dict[str, Any]) -> None:
    await set_context(conn, tenant_id=event["tenant_id"], is_ea=True)
    await repo.mark_failed(conn, UUID(event["payload"]["export_id"]))
