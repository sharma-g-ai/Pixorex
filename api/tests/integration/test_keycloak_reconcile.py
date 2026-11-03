"""docs/keycloak.md 8.4: the worker re-reads Keycloak's stored events and records lost ones."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from app.services import keycloak_events
from tests.integration.helpers import TARA

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)


class StoredEvents:
    """Keycloak's admin API, as far as the job uses it."""

    def __init__(self, events: list[dict[str, Any]]) -> None:
        self.stored = events
        self.calls: list[dict[str, Any]] = []
        self.lock: dict[str, Any] = {"disabled": False}

    async def events(
        self, *, date_from: str, types: list[str], first: int, max_results: int
    ) -> list[dict[str, Any]]:
        self.calls.append({"date_from": date_from, "types": types, "first": first})
        return self.stored[first : first + max_results]

    async def brute_force_status(self, kc_id: str) -> dict[str, Any]:
        return self.lock


def _stored(kc_id: str, kind: str = "LOGIN", minutes_ago: int = 60, **extra: Any) -> dict[str, Any]:
    at = NOW - timedelta(minutes=minutes_ago)
    return {
        "id": str(uuid.uuid4()),
        "time": int(at.timestamp() * 1000),
        "type": kind,
        "realmId": "pixorex",
        "clientId": "pixorex-mobile",
        "userId": kc_id,
        "ipAddress": "10.0.0.9",
        **extra,
    }


def _rows(owner_sql: Any, event_id: str) -> list[Any]:
    return owner_sql(
        "SELECT action, actor_user_id::text FROM audit_log"
        " WHERE category = 'sign_in' AND details->>'keycloak_event_id' = %s ORDER BY action",
        (event_id,),
    )


def _tara_signs_in_as(owner_sql: Any) -> str:
    kc_id = f"kc-{uuid.uuid4()}"
    owner_sql("UPDATE app_user SET keycloak_user_id = %s WHERE id = %s", (kc_id, TARA))
    return kc_id


async def test_lost_events_are_recorded_once(pool: Any, owner_sql: Any) -> None:
    """GIVEN Keycloak stored a sign-in the API never received WHEN the job runs twice
    THEN one audit row is added for it, as Tara."""
    kc_id = _tara_signs_in_as(owner_sql)
    login = _stored(kc_id)
    stranger = _stored(f"kc-{uuid.uuid4()}")  # no Pixorex user
    other = _stored(kc_id, "CODE_TO_TOKEN_ERROR")  # not recorded by the live path either
    keycloak: Any = StoredEvents([login, stranger, other])
    assert await keycloak_events.reconcile(pool, keycloak, now=NOW) == 1
    assert await keycloak_events.reconcile(pool, keycloak, now=NOW) == 0
    assert _rows(owner_sql, login["id"]) == [("sign_in.succeeded", TARA)]
    assert _rows(owner_sql, stranger["id"]) == _rows(owner_sql, other["id"]) == []
    assert keycloak.calls[0]["date_from"] == "2026-11-01"
    assert keycloak.calls[0]["types"] == ["LOGIN", "LOGIN_ERROR", "LOGOUT"]


async def test_reads_every_page(pool: Any, owner_sql: Any) -> None:
    kc_id = _tara_signs_in_as(owner_sql)
    stored = [_stored(kc_id, "LOGOUT") for _ in range(keycloak_events.PAGE + 1)]
    keycloak: Any = StoredEvents(stored)
    assert await keycloak_events.reconcile(pool, keycloak, now=NOW) == len(stored)
    assert [c["first"] for c in keycloak.calls] == [0, keycloak_events.PAGE]


async def test_a_recent_lost_wrong_code_still_records_the_lock(pool: Any, owner_sql: Any) -> None:
    """GIVEN a wrong code 5 minutes ago that locked Tara WHEN the job recovers it THEN the lock
    row is written; a wrong code from hours ago does not ask Keycloak about today's lock."""
    kc_id = _tara_signs_in_as(owner_sql)
    old = _stored(kc_id, "LOGIN_ERROR", minutes_ago=180, error="invalid_user_credentials")
    recent = _stored(kc_id, "LOGIN_ERROR", minutes_ago=5, error="invalid_user_credentials")
    keycloak: Any = StoredEvents([old, recent])
    keycloak.lock = {"disabled": True, "lastFailure": recent["time"]}
    assert await keycloak_events.reconcile(pool, keycloak, now=NOW) == 2
    assert [r[0] for r in _rows(owner_sql, recent["id"])] == ["sign_in.failed", "sign_in.locked"]
    assert [r[0] for r in _rows(owner_sql, old["id"])] == ["sign_in.failed"]


async def test_nothing_stored_reads_no_database(pool: Any) -> None:
    keycloak: Any = StoredEvents([])
    assert await keycloak_events.reconcile(pool, keycloak, now=NOW) == 0
