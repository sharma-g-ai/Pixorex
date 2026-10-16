"""Per-request values readable anywhere in the request (async-safe)."""

from contextvars import ContextVar

current_correlation_id: ContextVar[str] = ContextVar("correlation_id", default="")


def correlation_id() -> str:
    return current_correlation_id.get()
