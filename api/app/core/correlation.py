"""Gives every request a correlation_id, shared by logs, problem responses and audit rows."""

import re
import time
import uuid

import structlog
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.context import current_correlation_id
from app.core.problems import problem_response

HEADER = "x-correlation-id"
_SAFE_ID = re.compile(r"^[A-Za-z0-9-]{8,64}$")
_log = structlog.get_logger("pixorex.request")


def _incoming_id(scope: Scope) -> str:
    for name, value in scope["headers"]:
        if name == HEADER.encode():
            text: str = value.decode("latin-1")
            if _SAFE_ID.match(text):
                return text
    return str(uuid.uuid4())


class CorrelationMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        cid = _incoming_id(scope)
        token = current_correlation_id.set(cid)
        structlog.contextvars.bind_contextvars(correlation_id=cid)
        started = time.perf_counter()
        status = 500
        started_response = False

        async def send_with_id(message: Message) -> None:
            nonlocal status, started_response
            if message["type"] == "http.response.start":
                status, started_response = message["status"], True
                message.setdefault("headers", []).append((HEADER.encode(), cid.encode()))
            await send(message)

        try:
            await self.app(scope, receive, send_with_id)
        except Exception:
            # Unhandled errors: log the trace here, send a plain 500 without internals.
            _log.exception("unhandled_error")
            if not started_response:
                await problem_response(500, "internal")(scope, receive, send_with_id)
        finally:
            # Path only: query strings can carry emails or tokens.
            _log.info(
                "request",
                method=scope["method"],
                path=scope["path"],
                status=status,
                duration_ms=round((time.perf_counter() - started) * 1000, 1),
            )
            structlog.contextvars.unbind_contextvars("correlation_id")
            current_correlation_id.reset(token)
