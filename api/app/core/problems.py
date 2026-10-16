"""RFC 9457 problem+json for every error (contracts: common.yaml Problem)."""

from http import HTTPStatus
from typing import Any, cast

import psycopg
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.core.context import correlation_id

MEDIA_TYPE = "application/problem+json"

# Custom SQLSTATEs raised by the baseline triggers (api/migrations/baseline/README.md).
_SQLSTATE_PROBLEMS = {
    "PX001": (409, "locked-after-publish"),
    "PX002": (403, "own-scan"),
}


class ProblemError(Exception):
    """Raise from services; `code` becomes the type URI /problems/<code>."""

    def __init__(self, status: int, code: str, detail: str | None = None, **extra: Any) -> None:
        super().__init__(detail or code)
        self.status = status
        self.code = code
        self.detail = detail
        self.extra = extra


def problem_response(
    status: int, code: str, detail: str | None = None, **extra: Any
) -> JSONResponse:
    body: dict[str, Any] = {
        "type": f"/problems/{code}",
        "title": HTTPStatus(status).phrase,
        "status": status,
        "correlation_id": correlation_id(),
        **extra,
    }
    if detail:
        body["detail"] = detail
    return JSONResponse(body, status_code=status, media_type=MEDIA_TYPE)


def _code_for(status: int) -> str:
    return HTTPStatus(status).phrase.lower().replace(" ", "-")


async def _on_problem(_: Request, exc: Exception) -> JSONResponse:
    exc = cast(ProblemError, exc)
    return problem_response(exc.status, exc.code, exc.detail, **exc.extra)


async def _on_http(_: Request, exc: Exception) -> JSONResponse:
    exc = cast(HTTPException, exc)
    return problem_response(exc.status_code, _code_for(exc.status_code))


async def _on_validation(_: Request, exc: Exception) -> JSONResponse:
    exc = cast(RequestValidationError, exc)
    errors = [
        {"field": ".".join(str(p) for p in e["loc"][1:]) or str(e["loc"][0]), "message": e["msg"]}
        for e in exc.errors()
    ]
    return problem_response(400, "validation", "Some fields are not valid.", errors=errors)


async def _on_db(_: Request, exc: Exception) -> JSONResponse:
    exc = cast(psycopg.Error, exc)
    mapped = _SQLSTATE_PROBLEMS.get(exc.sqlstate or "")
    if mapped is None:
        raise exc  # not a known business rule: let it become a 500
    return problem_response(*mapped)


def install_problem_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ProblemError, _on_problem)
    app.add_exception_handler(HTTPException, _on_http)
    app.add_exception_handler(RequestValidationError, _on_validation)
    app.add_exception_handler(psycopg.Error, _on_db)
