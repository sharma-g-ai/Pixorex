"""POST /internal/keycloak-events: Keycloak's sign-in events become sign_in audit rows."""

import hashlib
import hmac
import json
import time
import uuid
from typing import Any

import pytest
from pydantic import SecretStr

from tests.integration.conftest import Api
from tests.integration.helpers import TARA, TENANT_A

SECRET = "test-events-secret"  # noqa: S105  (test value)
PATH = "/internal/keycloak-events"


@pytest.fixture
def events(api: Api) -> Api:
    app: Any = api.client.app
    app.state.settings = app.state.settings.model_copy(
        update={"keycloak_events_secret": SecretStr(SECRET)}
    )
    return api


def _event(kind: str = "LOGIN", **extra: Any) -> dict[str, Any]:
    return {
        "id": str(uuid.uuid4()),
        "type": kind,
        "time": int(time.time() * 1000),
        "realm": "pixorex",
        "client_id": "pixorex-mobile",
        "user_id": f"kc-{TARA}",
        "app_user_id": TARA,
        "tenant_id": TENANT_A,
        "session_id": "s1",
        "ip_address": "10.0.0.7",
        "error": None,
        "details": {"auth_method": "openid-connect"},
        **extra,
    }


def _send(api: Api, event: dict[str, Any], secret: str = SECRET) -> Any:
    body = json.dumps(event).encode()
    signature = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return api.client.post(
        PATH,
        content=body,
        headers={
            "Content-Type": "application/json",
            "X-Pixorex-Signature": signature,
            "X-Pixorex-Event-Id": event["id"],
        },
    )


def _rows(owner_sql: Any, event_id: str) -> list[Any]:
    return owner_sql(
        "SELECT action, summary, actor_user_id::text, details->>'ip_address' FROM audit_log"
        " WHERE category = 'sign_in' AND details->>'keycloak_event_id' = %s ORDER BY action",
        (event_id,),
    )


def test_signed_events_are_recorded_once(events: Api, owner_sql: Any) -> None:
    login = _event()
    assert _send(events, login).status_code == 204
    assert _send(events, login).status_code == 204  # a retried delivery
    assert _rows(owner_sql, login["id"]) == [
        ("sign_in.succeeded", "Signed in to the mobile app", TARA, "10.0.0.7")
    ]
    failed = _event("LOGIN_ERROR", error="invalid_user_credentials", client_id="pixorex-web")
    assert _send(events, failed).status_code == 204
    assert _rows(owner_sql, failed["id"])[0][:2] == (
        "sign_in.failed",
        "Sign-in to the dashboard failed: wrong code",
    )
    logout = _event("LOGOUT")
    assert _send(events, logout).status_code == 204
    assert _rows(owner_sql, logout["id"])[0][0] == "sign_in.session_ended"


def test_unsigned_unknown_and_unhandled_events(events: Api, owner_sql: Any) -> None:
    event = _event()
    response = _send(events, event, secret="wrong")  # noqa: S106  (test value)
    assert response.status_code == 401 and response.json()["type"] == "/problems/unauthorized"
    assert _rows(owner_sql, event["id"]) == []
    for skipped in (
        _event(app_user_id=None, tenant_id=None),  # no Pixorex account behind the login
        _event(app_user_id=str(uuid.uuid4())),  # not a user of that tenant
        _event("REFRESH_TOKEN_ERROR", error="invalid_token"),  # no handling in the doc
    ):
        assert _send(events, skipped).status_code == 204
        assert _rows(owner_sql, skipped["id"]) == []


def test_without_a_secret_the_endpoint_is_off(api: Api) -> None:
    assert _send(api, _event()).status_code == 404


def test_a_lock_is_recorded_once(events: Api, owner_sql: Any) -> None:
    keycloak: Any = events.keycloak
    last_failure = int(time.time() * 1000)
    keycloak.lock = {"disabled": True, "numFailures": 5, "lastFailure": last_failure}
    for _ in range(2):  # the fifth wrong code, then a try while locked
        wrong = _event("LOGIN_ERROR", error="invalid_user_credentials")
        assert _send(events, wrong).status_code == 204
    locks = owner_sql(
        "SELECT actor_type, object_id::text, summary FROM audit_log WHERE action = 'sign_in.locked'"
        " AND details->>'lock_key' = %s",
        (f"{TARA}:{last_failure}",),
    )
    assert locks == [("system", TARA, "Sign-in locked for 30 minutes after 5 wrong codes")]
