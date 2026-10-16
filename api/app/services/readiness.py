"""Readiness checks (contract 4.4): each dependency is ok or fail, nothing else is exposed."""

import asyncio
from collections.abc import Awaitable, Callable
from typing import Literal

import httpx
import structlog
from psycopg_pool import AsyncConnectionPool

from app.core.config import Settings

Check = Literal["ok", "fail"]
_log = structlog.get_logger("pixorex.readiness")


async def _database(pool: AsyncConnectionPool) -> None:
    async with pool.connection() as conn:
        await conn.execute("SELECT 1")


async def _http_ok(client: httpx.AsyncClient, url: str) -> None:
    response = await client.get(url)
    response.raise_for_status()


def _url(base: object, path: str) -> str:
    return str(base).rstrip("/") + path


async def _run(name: str, probe: Awaitable[None], limit_s: float) -> Check:
    try:
        await asyncio.wait_for(probe, limit_s)
        return "ok"
    except Exception as exc:  # any failure means "fail"; the reason goes to logs only
        _log.warning("dependency_not_ready", dependency=name, error=type(exc).__name__)
        return "fail"


async def check_all(
    settings: Settings, pool: AsyncConnectionPool, client: httpx.AsyncClient
) -> dict[str, Check]:
    probes: dict[str, Callable[[], Awaitable[None]]] = {
        "database": lambda: _database(pool),
        "keycloak": lambda: _http_ok(
            client, _url(settings.keycloak_realm_url, "/.well-known/openid-configuration")
        ),
        "minio": lambda: _http_ok(client, _url(settings.minio_url, "/minio/health/ready")),
        # standbyok: a standby node can still serve reads.
        "vault": lambda: _http_ok(
            client, _url(settings.vault_url, "/v1/sys/health?standbyok=true")
        ),
    }
    timeout = settings.readiness_timeout_s
    results = await asyncio.gather(*(_run(n, p(), timeout) for n, p in probes.items()))
    return dict(zip(probes, results, strict=True))
