"""Repeat-safe creates (contract "Repeat-safe create", CONSTITUTION: creates take
Idempotency-Key). Same key + same request within 24 hours -> the first answer again, and the
change is not made twice; same key + another request -> 409 idempotency-conflict.

The key is checked, the work done and the answer stored in one transaction (the request's),
so a request is either fully done and remembered, or neither. A failed request (4xx/5xx)
stores nothing, so it can be sent again. Keys belong to one user.
Scans use their own key, scan.client_capture_id (contract 2.21)."""

import hashlib
from collections.abc import Awaitable, Callable
from uuid import UUID

from fastapi import Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.auth.context import Session
from app.core.problems import ProblemError
from app.repositories import idempotency as repo

KEPT_HEADERS = ("content-type", "content-disposition")


def json_response(model: BaseModel, status_code: int) -> Response:
    return JSONResponse(model.model_dump(mode="json"), status_code=status_code)


async def _fingerprint(request: Request, operation: str) -> str:
    """The endpoint, its path (ids in it) and the exact body bytes."""
    digest = hashlib.sha256()
    for part in (operation.encode(), b"\n", request.url.path.encode(), b"\n"):
        digest.update(part)
    digest.update(await request.body())
    return digest.hexdigest()


async def once(
    session: Session,
    request: Request,
    key: UUID,
    run: Callable[[], Awaitable[Response]],
) -> Response:
    caller = session.caller
    route = request.scope.get("route")
    operation = str(getattr(route, "operation_id", None) or request.url.path)
    fingerprint = await _fingerprint(request, operation)
    await repo.lock(session.conn, caller.tenant_id, caller.user_id, key)
    stored = await repo.find(session.conn, caller.tenant_id, caller.user_id, key)
    if stored is not None:
        if stored["operation"] != operation or stored["request_hash"] != fingerprint:
            raise ProblemError(
                409,
                "idempotency-conflict",
                "This Idempotency-Key was already used for a different request.",
            )
        return Response(
            content=bytes(stored["body"]),
            status_code=stored["status_code"],
            headers=stored["headers"],
        )
    response = await run()
    if 200 <= response.status_code < 300:
        await repo.save(
            session.conn,
            tenant_id=caller.tenant_id,
            user_id=caller.user_id,
            key=key,
            operation=operation,
            request_hash=fingerprint,
            status_code=response.status_code,
            headers={k: v for k, v in response.headers.items() if k in KEPT_HEADERS},
            body=bytes(response.body),
        )
    return response
