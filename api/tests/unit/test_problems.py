import psycopg
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel

from app.core.problems import ProblemError


class _Body(BaseModel):
    name: str


def _add_routes(app: FastAPI) -> None:
    @app.get("/boom")
    async def boom() -> None:
        raise RuntimeError("password=hunter2")

    @app.get("/conflict")
    async def conflict() -> None:
        raise ProblemError(409, "invalid-state", "Already decided.")

    @app.get("/frozen")
    async def frozen() -> None:
        error = psycopg.errors.RaiseException("frozen")
        error.sqlstate = "PX001"  # type: ignore[misc]
        raise error

    @app.post("/things")
    async def create(body: _Body) -> None:
        return None


def _get(app_and_client: tuple, method: str, path: str, **kwargs: object) -> dict:
    app, client = app_and_client
    _add_routes(app)
    response = client.request(method, path, **kwargs)  # type: ignore[arg-type]
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json()["correlation_id"] == response.headers["x-correlation-id"]
    return response.json() | {"_status": response.status_code}


def test_unknown_error_is_500_without_internals(app_and_client: tuple) -> None:
    body = _get(app_and_client, "GET", "/boom")
    assert body["_status"] == 500
    assert body["type"] == "/problems/internal"
    assert "hunter2" not in str(body)


def test_service_problem(app_and_client: tuple) -> None:
    body = _get(app_and_client, "GET", "/conflict")
    assert (body["_status"], body["type"], body["detail"]) == (
        409,
        "/problems/invalid-state",
        "Already decided.",
    )


def test_trigger_sqlstate_maps_to_problem(app_and_client: tuple) -> None:
    body = _get(app_and_client, "GET", "/frozen")
    assert (body["_status"], body["type"]) == (409, "/problems/locked-after-publish")


def test_validation_is_400_with_field_errors(app_and_client: tuple) -> None:
    body = _get(app_and_client, "POST", "/things", json={})
    assert body["_status"] == 400
    assert body["errors"][0]["field"] == "name"


def test_unknown_route_is_problem(app_and_client: tuple) -> None:
    body = _get(app_and_client, "GET", "/nope")
    assert (body["_status"], body["type"]) == (404, "/problems/not-found")


def test_keeps_a_safe_incoming_correlation_id(client: TestClient) -> None:
    cid = "3f1c2a9e-1111-4222-8333-444455556666"
    assert (
        client.get("/api/v1/health", headers={"X-Correlation-Id": cid}).headers["x-correlation-id"]
        == cid
    )
    unsafe = client.get("/api/v1/health", headers={"X-Correlation-Id": "<script>"})
    assert unsafe.headers["x-correlation-id"] != "<script>"
