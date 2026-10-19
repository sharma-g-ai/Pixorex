"""The worker process: sends due outbox events and runs the scheduled jobs.

python -m app.workers.runner        (Docker Compose service "worker")
"""

import asyncio
import signal
import time

import structlog

from app.core.db import Conn
from app.core.logging import configure_logging
from app.workers import jobs, outbox
from app.workers.settings import WorkerSettings, get_worker_settings

_log = structlog.get_logger("pixorex.worker")


def _pool(settings: WorkerSettings):  # type: ignore[no-untyped-def]
    from psycopg.rows import dict_row
    from psycopg_pool import AsyncConnectionPool

    return AsyncConnectionPool(
        settings.worker_database_url.get_secret_value(),
        connection_class=Conn,
        min_size=1,
        max_size=2,
        kwargs={"row_factory": dict_row, "application_name": "pixorex-worker"},
        check=AsyncConnectionPool.check_connection,
        open=False,
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
    _log.info("worker_started")
    next_jobs = 0.0
    try:
        while not stop.is_set():
            try:
                if time.monotonic() >= next_jobs:
                    totals = await jobs.run_all(pool)
                    if any(totals.values()):
                        _log.info("jobs_done", **totals)
                    next_jobs = time.monotonic() + settings.worker_jobs_every_s
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
        await pool.close()
        _log.info("worker_stopped")


if __name__ == "__main__":
    asyncio.run(main())
