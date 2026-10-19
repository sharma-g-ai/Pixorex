"""Integration tests against a real PostgreSQL, as the API role, under RLS.

Needs PIXOREX_TEST_ADMIN_URL: a superuser connection to a server where the roles of
setup_roles_and_database.sql exist with the local-only passwords (Docker Compose does
this). A throwaway database is created, migrated and seeded, then dropped.
Keycloak and email are replaced by fakes; tokens are signed with a test key.
"""

import asyncio
import os
import subprocess
import sys
import uuid
from collections.abc import AsyncIterator, Callable, Iterator
from pathlib import Path
from typing import Any

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from app.core.db import Conn
from app.main import create_app
from app.services import mail
from tests.conftest import make_settings
from tests.integration.helpers import ISSUER, FakeJwks, FakeKeycloak, make_token

ADMIN_URL = os.environ.get("PIXOREX_TEST_ADMIN_URL")
pytestmark = pytest.mark.skipif(not ADMIN_URL, reason="PIXOREX_TEST_ADMIN_URL not set")
API_DIR = Path(__file__).resolve().parents[2]

if sys.platform == "win32":  # psycopg's async mode needs the selector loop on Windows
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())  # type: ignore[attr-defined]


@pytest.fixture(scope="session")
def database() -> Iterator[dict[str, str]]:
    assert ADMIN_URL
    name = f"pixorex_test_{uuid.uuid4().hex[:8]}"
    server = conninfo_to_dict(ADMIN_URL)
    with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
        admin.execute(f"CREATE DATABASE {name} OWNER pixorex_owner")
    where = f"{server.get('host', 'localhost')}:{server.get('port', '5432')}/{name}"
    owner = f"postgresql://pixorex_owner:local-only@{where}"
    env = {**os.environ, "PIXOREX_MIGRATIONS_DATABASE_URL": owner}
    try:
        for command in (
            ["alembic", "upgrade", "head"],
            [sys.executable, "scripts/seed_synthetic.py"],
        ):
            subprocess.run(command, cwd=API_DIR, env=env, check=True, capture_output=True)
        yield {
            "app": f"postgresql://pixorex_app:local-only@{where}",
            "owner": owner,
            "worker": f"postgresql://pixorex_worker:local-only@{where}",
        }
    finally:
        with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
            admin.execute(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


class Api:
    """A TestClient that signs in as someone. Every call carries X-Device-Id."""

    def __init__(self, client: TestClient, sent: list[dict[str, str]], keycloak: FakeKeycloak):
        self.client, self.sent, self.keycloak = client, sent, keycloak

    def call(
        self,
        method: str,
        path: str,
        user: str | None = None,
        *,
        device: str = "dev-1",
        token: str | None = None,
        **kwargs: Any,
    ) -> Any:
        headers = {"X-Device-Id": device, **kwargs.pop("headers", {})}
        if token or user:
            headers["Authorization"] = f"Bearer {token or make_token(user or '')}"
        return self.client.request(method, f"/api/v1{path}", headers=headers, **kwargs)

    def get(self, path: str, user: str | None = None, **kw: Any) -> Any:
        return self.call("GET", path, user, **kw)

    def post(self, path: str, user: str | None = None, **kw: Any) -> Any:
        return self.call("POST", path, user, **kw)

    def put(self, path: str, user: str | None = None, **kw: Any) -> Any:
        return self.call("PUT", path, user, **kw)


@pytest.fixture
def api(database: dict[str, str], monkeypatch: pytest.MonkeyPatch) -> Iterator[Api]:
    sent: list[dict[str, str]] = []

    async def fake_send(settings: Any, *, to: str, token: str, role: str) -> bool:
        sent.append({"to": to, "token": token, "role": role})
        return True

    monkeypatch.setattr(mail, "send_invite", fake_send)
    app = create_app(make_settings(database_url=database["app"], oidc_issuer=ISSUER))
    keycloak = FakeKeycloak()
    with TestClient(app, raise_server_exceptions=False) as client:
        app.state.jwks = FakeJwks()
        app.state.keycloak = keycloak
        yield Api(client, sent, keycloak)


@pytest.fixture
def owner_sql(database: dict[str, str]) -> Callable[[str, tuple[Any, ...]], list[Any]]:
    """Read or fix rows as the owner (bypasses RLS): for test setup and checks only."""

    def run(sql: str, params: tuple[Any, ...] = ()) -> list[Any]:
        with psycopg.connect(database["owner"], autocommit=True) as conn:
            cur = conn.execute(sql, params)
            return cur.fetchall() if cur.description else []

    return run


@pytest.fixture
async def pool(database: dict[str, str]) -> AsyncIterator[Any]:
    """A connection pool as the worker role (pixorex_worker)."""
    worker_pool: Any = AsyncConnectionPool(
        database["worker"], connection_class=Conn, kwargs={"row_factory": dict_row}, open=False
    )
    await worker_pool.open()
    yield worker_pool
    await worker_pool.close()
