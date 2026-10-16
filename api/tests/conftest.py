from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


def make_settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "env": "test",
        "database_url": "postgresql://pixorex_app:x@127.0.0.1:1/pixorex",
        "oidc_issuer": "http://127.0.0.1:1/realms/pixorex",
        "minio_url": "http://127.0.0.1:1",
        "vault_url": "http://127.0.0.1:1",
        **overrides,
    }
    return Settings(**values)  # type: ignore[arg-type]


@pytest.fixture
def app_and_client() -> Iterator[tuple]:
    app = create_app(make_settings())
    with TestClient(app, raise_server_exceptions=False) as client:
        yield app, client


@pytest.fixture
def client(app_and_client: tuple) -> TestClient:
    return app_and_client[1]
