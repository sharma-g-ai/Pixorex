"""The worker process: sends due outbox events and runs the scheduled jobs.

python -m app.workers.runner        (Docker Compose services "worker" and "extraction-worker",
                                    split by PIXOREX_WORKER_ROLE)

The extraction container runs PIXOREX_EXTRACTION_CONCURRENCY claim loops side by side; the
other roles run one loop that also does the scheduled jobs.
"""

import asyncio
import signal
import time

import httpx
import structlog

from app.auth.keycloak_admin import KeycloakAdmin
from app.core.db import Conn, Pool
from app.core.logging import configure_logging
from app.services import keycloak_events
from app.workers import jobs, outbox
from app.workers.settings import WorkerSettings, get_worker_settings

_log = structlog.get_logger("pixorex.worker")


def _pool(settings: WorkerSettings):  # type: ignore[no-untyped-def]
    from psycopg.rows import dict_row
    from psycopg_pool import AsyncConnectionPool

    # The extraction container needs a connection for each claim loop and one to spare; the
    # other roles use one at a time (the scheduled jobs and the outbox run in turn).
    loops = settings.extraction_concurrency if settings.worker_role == "extraction" else 1
    return AsyncConnectionPool(
        settings.worker_database_url.get_secret_value(),
        connection_class=Conn,
        min_size=1,
        max_size=loops + 1,
        kwargs={"row_factory": dict_row, "application_name": "pixorex-worker"},
        check=AsyncConnectionPool.check_connection,
        open=False,
    )


async def claim_loop(pool: Pool, settings: WorkerSettings, stop: asyncio.Event) -> None:
    """Runs due outbox events until told to stop; waits worker_tick_s when none is due."""
    while not stop.is_set():
        try:
            handled = await outbox.run_due(pool, settings, stop=stop)
            if handled:
                _log.info("outbox_done", events=handled)
        except Exception:
            _log.exception("worker_tick_failed")
        try:
            await asyncio.wait_for(stop.wait(), timeout=settings.worker_tick_s)
        except TimeoutError:
            pass


async def run_claim_loops(pool: Pool, settings: WorkerSettings, stop: asyncio.Event) -> None:
    """The extraction container: extraction_concurrency claim loops in this process, so that
    many AI calls are open at once. FOR UPDATE SKIP LOCKED and the lease keep the loops off
    each other's events."""
    await asyncio.gather(
        *(claim_loop(pool, settings, stop) for _ in range(settings.extraction_concurrency))
    )


async def main() -> None:
    settings = get_worker_settings()
    configure_logging(settings.log_level)
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            asyncio.get_running_loop().add_signal_handler(sig, stop.set)
        except NotImplementedError:  # Windows: Ctrl+C still stops it
            pass
    pool = _pool(settings)
    await pool.open(wait=True, timeout=60)
    http = httpx.AsyncClient()
    keycloak = (
        KeycloakAdmin(
            realm_url=settings.keycloak_realm_url,
            client_id=settings.keycloak_admin_client_id,
            client_secret=settings.keycloak_admin_secret,
            http=http,
        )
        if settings.keycloak_admin_secret
        else None
    )
    if settings.worker_role == "extraction":
        keycloak = None  # scheduled jobs and the Keycloak re-read belong to the general worker
    extraction = settings.worker_role == "extraction"
    _log.info(
        "worker_started",
        role=settings.worker_role,
        claim_loops=settings.extraction_concurrency if extraction else 1,
    )
    next_jobs = next_keycloak = 0.0
    try:
        if extraction:
            await run_claim_loops(pool, settings, stop)
            return
        while not stop.is_set():
            try:
                if settings.worker_role != "extraction" and time.monotonic() >= next_jobs:
                    totals = await jobs.run_all(pool)
                    if any(totals.values()):
                        _log.info("jobs_done", **totals)
                    next_jobs = time.monotonic() + settings.worker_jobs_every_s
                if keycloak and time.monotonic() >= next_keycloak:
                    next_keycloak = time.monotonic() + settings.worker_keycloak_every_s
                    try:
                        await keycloak_events.reconcile(pool, keycloak)
                    except (httpx.HTTPError, RuntimeError) as exc:
                        _log.warning("keycloak_reconcile_failed", error=type(exc).__name__)
                sent = await outbox.run_due(pool, settings)
                if sent:
                    _log.info("outbox_done", events=sent)
            except Exception:
                _log.exception("worker_tick_failed")
            try:
                await asyncio.wait_for(stop.wait(), timeout=settings.worker_tick_s)
            except TimeoutError:
                pass
    finally:
        await http.aclose()
        await pool.close()
        _log.info("worker_stopped")


if __name__ == "__main__":
    asyncio.run(main())
