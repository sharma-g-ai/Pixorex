"""Keycloak's sign-in events become sign_in audit rows (docs/keycloak.md 5.4, 8.3; PX-01-T04).

LOGIN, LOGIN_ERROR and LOGOUT are recorded. The listener also forwards CODE_TO_TOKEN_ERROR
and REFRESH_TOKEN_ERROR; the doc gives them no handling, so they are accepted and not stored.
Events for a login with no Pixorex account (no tenant) can't be recorded in any tenant.
Every event is stored once, keyed on Keycloak's event id (deliveries retry).
TODO (docs/keycloak.md 8.4): the reconciliation job that re-reads Keycloak's stored events.
TODO (D-08, contracts 1.4-1.5): phone change, once the listener sends that event."""

from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import httpx
import structlog
from pydantic import BaseModel, Field, ValidationError

from app.auth.context import set_context
from app.auth.keycloak_admin import KeycloakAdmin
from app.core.db import Pool
from app.repositories import audit

_log = structlog.get_logger("pixorex.keycloak_events")
CATEGORY = "sign_in"
LOCK_ERRORS = {"invalid_user_credentials", "user_temporarily_disabled"}
APPS = {"pixorex-mobile": "the mobile app", "pixorex-web": "the dashboard"}
FAILURES = {
    "invalid_user_credentials": "wrong code",
    "user_temporarily_disabled": "sign-in is locked",
    "expired_code": "the code expired",
}


class KeycloakEvent(BaseModel):
    id: str
    type: str
    time: int  # milliseconds since 1970
    client_id: str | None = None
    user_id: str | None = None  # the Keycloak user
    app_user_id: UUID | None = None
    tenant_id: UUID | None = None
    ip_address: str | None = None
    error: str | None = None
    details: dict[str, str] = Field(default_factory=dict)


def _at(ms: int) -> datetime:
    return datetime.fromtimestamp(ms / 1000, tz=UTC)


def _row(event: KeycloakEvent) -> tuple[str, str] | None:
    app = APPS.get(event.client_id or "")
    where = f" to {app}" if app else ""
    if event.type == "LOGIN":
        return "sign_in.succeeded", f"Signed in{where}"
    if event.type == "LOGIN_ERROR":
        reason = FAILURES.get(event.error or "", event.error or "unknown reason")
        return "sign_in.failed", f"Sign-in{where} failed: {reason}"
    if event.type == "LOGOUT":
        return "sign_in.session_ended", f"Sign-in session{where} ended"
    return None


async def _lock_state(keycloak: KeycloakAdmin, event: KeycloakEvent) -> dict[str, Any] | None:
    """Keycloak locks asynchronously and has no lock event, so the state is read after a
    wrong code, and again on the next attempt while locked (docs/keycloak.md 5.4)."""
    if event.type != "LOGIN_ERROR" or event.error not in LOCK_ERRORS or not event.user_id:
        return None
    try:
        status = await keycloak.brute_force_status(event.user_id)
    except (httpx.HTTPError, RuntimeError) as exc:
        _log.warning("lock_state_unavailable", error=type(exc).__name__)
        return None
    return status if status.get("disabled") and status.get("lastFailure") else None


async def handle(pool: Pool, keycloak: KeycloakAdmin, raw: bytes) -> None:
    try:
        event = KeycloakEvent.model_validate_json(raw)
    except ValidationError:
        _log.warning("keycloak_event_unreadable")
        return
    row = _row(event)
    if row is None or event.tenant_id is None or event.app_user_id is None:
        return
    lock = await _lock_state(keycloak, event)
    async with pool.connection() as conn, conn.transaction():
        await set_context(conn, tenant_id=event.tenant_id, is_ea=True)
        cur = await conn.execute("SELECT 1 FROM app_user WHERE id = %s", (event.app_user_id,))
        if await cur.fetchone() is None:
            return  # not a user of that tenant
        await conn.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", (f"kc-event:{event.id}",)
        )
        seen = await audit.has_detail(
            conn,
            tenant_id=event.tenant_id,
            category=CATEGORY,
            key="keycloak_event_id",
            value=event.id,
        )
        if not seen:
            details = {
                "keycloak_event_id": event.id,
                "client_id": event.client_id,
                "ip_address": event.ip_address,
                "error": event.error,
            }
            action, summary = row
            await audit.record_event(
                conn,
                tenant_id=event.tenant_id,
                actor_user_id=event.app_user_id,
                category=CATEGORY,
                action=action,
                summary=summary,
                details={k: v for k, v in details.items() if v is not None},
                occurred_at=_at(event.time),
            )
        if lock is None:
            return
        key = f"{event.app_user_id}:{lock['lastFailure']}"  # one row per lock
        locked = await audit.has_detail(
            conn, tenant_id=event.tenant_id, category=CATEGORY, key="lock_key", value=key
        )
        if not locked:
            await audit.record_event(
                conn,
                tenant_id=event.tenant_id,
                actor_user_id=None,
                category=CATEGORY,
                action="sign_in.locked",
                summary="Sign-in locked for 30 minutes after 5 wrong codes",
                details={"lock_key": key, "keycloak_event_id": event.id},
                occurred_at=_at(int(lock["lastFailure"])),
                object_type="user",
                object_id=event.app_user_id,
            )
