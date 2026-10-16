from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.routers import operations


def test_health_needs_no_token(client: TestClient) -> None:
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_when_all_dependencies_ok(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    checks = {"database": "ok", "keycloak": "ok", "minio": "ok", "vault": "ok"}
    monkeypatch.setattr(operations, "check_all", AsyncMock(return_value=checks))
    response = client.get("/api/v1/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready", "checks": checks}


def test_not_ready_lists_each_dependency(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    checks = {"database": "fail", "keycloak": "ok", "minio": "ok", "vault": "ok"}
    monkeypatch.setattr(operations, "check_all", AsyncMock(return_value=checks))
    response = client.get("/api/v1/ready")
    assert response.status_code == 503
    assert response.headers["content-type"] == "application/problem+json"
    body = response.json()
    assert body["type"] == "/problems/not-ready"
    assert body["checks"] == checks
