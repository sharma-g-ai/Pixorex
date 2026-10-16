"""Operations probes (contracts 4.3 /health, 4.4 /ready). Public, no data."""

from typing import Literal

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.core.problems import problem_response
from app.services.readiness import Check, check_all

router = APIRouter(tags=["Operations"])


class Health(BaseModel):
    status: Literal["ok"]


class Readiness(BaseModel):
    status: Literal["ready", "not_ready"]
    checks: dict[str, Check]


@router.get("/health", operation_id="getHealth")
async def get_health() -> Health:
    return Health(status="ok")


@router.get("/ready", operation_id="getReadiness", response_model=Readiness)
async def get_readiness(request: Request) -> Readiness | JSONResponse:
    state = request.app.state
    checks = await check_all(state.settings, state.pool, state.http)
    if all(v == "ok" for v in checks.values()):
        return Readiness(status="ready", checks=checks)
    return problem_response(503, "not-ready", checks=checks)
