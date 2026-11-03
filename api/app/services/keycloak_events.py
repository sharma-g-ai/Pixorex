"""Keycloak's sign-in events become sign_in audit rows (docs/keycloak.md 5.4, 8.3; PX-01-T04).

LOGIN, LOGIN_ERROR and LOGOUT are recorded. The listener also forwards CODE_TO_TOKEN_ERROR
and REFRESH_TOKEN_ERROR; the doc gives them no handling, so they are accepted and not stored.
Events for a login with no Pixorex account (no tenant) can't be recorded in any tenant.
Every event is stored once, keyed on Keycloak's event id (deliveries retry).
reconcile() re-reads Keycloak's stored events for any the listener lost (docs/keycloak.md 8.4).
TODO (D-08, contracts 1.4-1.5): phone change, once the listener sends that event."""

from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import httpx
import structlog
from pydantic import BaseModel, Field, ValidationError

from app.auth.context import set_context
from app.auth.keycloak_admin import KeycloakAdmin
from app.core.db import Pool
from app.repositories import audit, users

_log = structlog.get_logger("pixorex.keycloak_events")
CATEGORY = "sign_in"
LOCK_ERRORS = {"invalid_user_credentials", "user_temporarily_disabled"}
APPS = {"pixorex-mobile": "the mobile app", "pixorex-web": "the dashboard"}
FAILURES = {
    "invalid_user_credentials": "wrong code",
    "user_temporarily_disabled": "sign-in is locked",
    "expired_code": "the code expired",
}
STORED_TYPES = ["LOGIN", "LOGIN_ERROR", "LOGOUT"]
PAGE = 200
LOCK_WINDOW = timedelta(minutes=30)  # an older wrong code can't explain today's lock state


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
    await record(pool, keycloak, event)


async def record(
    pool: Pool, keycloak: KeycloakAdmin, event: KeycloakEvent, *, check_lock: bool = True
) -> None:
    row = _row(event)
    if row is None or event.tenant_id is None or event.app_user_id is None:
        return
    lock = await _lock_state(keycloak, event) if check_lock else None
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


async def _stored(keycloak: KeycloakAdmin, date_from: str) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    while True:
        page = await keycloak.events(
            date_from=date_from, types=STORED_TYPES, first=len(found), max_results=PAGE
        )
        found += page
        if len(page) < PAGE:
            return found


async def reconcile(pool: Pool, keycloak: KeycloakAdmin, *, now: datetime | None = None) -> int:
    """docs/keycloak.md 8.4: the listener's retry queue lives in memory and is lost if Keycloak
    restarts, so the worker re-reads the stored events since yesterday and records the ones
    missing. Stored events carry no tenant, so each Keycloak user is matched to its app_user
    tenant by tenant. Returns how many events were added."""
    now = now or datetime.now(UTC)
    stored = [
        e
        for e in await _stored(keycloak, (now - timedelta(days=1)).date().isoformat())
        if e.get("id") and e.get("userId")
    ]
    if not stored:
        return 0
    kc_ids = sorted({str(e["userId"]) for e in stored})
    event_ids = [str(e["id"]) for e in stored]
    owners: dict[str, tuple[UUID, UUID]] = {}  # Keycloak user -> (tenant, app_user)
    seen: set[str] = set()
    async with pool.connection() as conn:
        tenants = [r["id"] for r in await (await conn.execute("SELECT id FROM tenant")).fetchall()]
        for tenant_id in tenants:
            async with conn.transaction():
                await set_context(conn, tenant_id=tenant_id, is_ea=True)
                mine = await users.by_keycloak_ids(conn, kc_ids)
                if not mine:
                    continue
                owners |= {kc: (tenant_id, user) for kc, user in mine.items()}
                seen |= await audit.details_present(
                    conn,
                    tenant_id=tenant_id,
                    category=CATEGORY,
                    key="keycloak_event_id",
                    values=event_ids,
                )
    added = 0
    for raw in stored:
        owner = owners.get(str(raw["userId"]))
        if owner is None or str(raw["id"]) in seen:
            continue
        event = KeycloakEvent(
            id=str(raw["id"]),
            type=str(raw.get("type")),
            time=int(raw.get("time") or 0),
            client_id=raw.get("clientId"),
            user_id=str(raw["userId"]),
            tenant_id=owner[0],
            app_user_id=owner[1],
            ip_address=raw.get("ipAddress"),
            error=raw.get("error"),
            details=raw.get("details") or {},
        )
        if _row(event) is None:
            continue
        await record(pool, keycloak, event, check_lock=now - _at(event.time) < LOCK_WINDOW)
        added += 1
    if added:
        _log.warning("keycloak_events_recovered", count=added)
    return added
