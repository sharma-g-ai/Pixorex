"""The worker's AI extraction (FR-4.4-4.9): from upload-complete to ready_to_review."""

from typing import Any

import pytest

from app.core import storage
from app.services import ai_proxy
from app.workers import outbox
from app.workers.settings import WorkerSettings
from tests.integration.capture_setup import JPEG, _confirmed, _key, _problem
from tests.integration.conftest import Api
from tests.integration.helpers import TARA


def _settings(database: dict[str, str]) -> WorkerSettings:
    return WorkerSettings(  # type: ignore[call-arg]
        worker_database_url=database["worker"],
        minio_access_key="k",
        minio_secret_key="s",  # noqa: S106  (test value)
        portkey_api_key="pk",
        portkey_config_id="pc-test",
    )


@pytest.fixture
def ai(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    """Fake photo storage and a fake AI answer; records what the AI was asked."""
    seen: dict[str, Any] = {"calls": 0}

    async def get(config: Any, key: str) -> bytes:
        return JPEG

    async def extract(http: Any, config: Any, **kwargs: Any) -> ai_proxy.Extraction:
        seen["calls"] += 1
        seen["kwargs"] = kwargs
        outcome = seen.get("outcome")
        if isinstance(outcome, Exception):
            raise outcome
        return ai_proxy.Extraction(
            fields={
                "serial": {"value": "SN-77", "confidence": 0.42, "format_ok": True},
                "voltage": {"value": None, "confidence": None, "format_ok": True},
            },
            detected_label="Motor nameplate",
            suggested_type="Motor",
            type_confidence=0.91,
            tokens_in=1200,
            tokens_out=80,
        )

    monkeypatch.setattr(storage, "get", get)
    monkeypatch.setattr(ai_proxy, "extract", extract)
    return seen


async def _run(pool: Any, owner_sql: Any, database: dict[str, str]) -> None:
    owner_sql(
        "UPDATE outbox_event SET next_run_at = now() - interval '1 second' WHERE status = 'pending'"
    )

    async def no_mail(settings: Any, **_: str) -> None:
        return None

    await outbox.run_due(pool, _settings(database), send=no_mail, limit=1000)


async def test_an_upload_is_extracted_and_ready_to_review(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
) -> None:
    sid = _confirmed(api, unit)["scan_id"]
    await _run(pool, owner_sql, database)
    assert ai["calls"] >= 1
    asked = ai["kwargs"]
    assert asked["type_name"] == "Motor" and [f["field_key"] for f in asked["fields"]] == [
        "serial",
        "voltage",
    ]
    assert asked["photos"] == [(JPEG, "image/jpeg")]

    scan = api.get(f"/scans/{sid}", TARA).json()
    assert scan["processing_status"] == "ready_to_review"
    assert scan["latest_attempt"]["status"] == "succeeded"
    assert scan["latest_attempt"]["detected_label"] == "Motor nameplate"
    assert scan["latest_attempt"]["suggested_type_id"] == unit["type"]
    by_key = {f["field_key"]: f for f in scan["fields"]}
    assert (by_key["serial"]["ai_value"], by_key["serial"]["flag_reasons"]) == (
        "SN-77",
        ["low_confidence"],
    )
    assert by_key["voltage"]["ai_value"] is None and by_key["voltage"]["flag_reasons"] == []
    tokens = owner_sql(
        "SELECT tokens_in, tokens_out FROM extraction_attempt WHERE scan_id = %s", (sid,)
    )
    assert tokens == [(1200, 80)]


async def test_a_failed_extraction_allows_retries_then_a_retake(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
) -> None:
    sid = _confirmed(api, unit)["scan_id"]
    ai["outcome"] = ai_proxy.AiUnavailableError("down")
    await _run(pool, owner_sql, database)
    status = "SELECT processing_status FROM scan WHERE id = %s"
    assert owner_sql(status, (sid,)) == [("failed",)]

    ai["outcome"] = TimeoutError("slow")
    assert api.post(f"/scans/{sid}/retry-extraction", TARA, headers=_key()).status_code == 202
    await _run(pool, owner_sql, database)
    attempts = owner_sql(
        "SELECT attempt_no, status FROM extraction_attempt WHERE scan_id = %s ORDER BY 1", (sid,)
    )
    assert attempts == [(1, "failed"), (2, "timed_out")]
    assert owner_sql(status, (sid,)) == [("failed",)]

    assert api.post(f"/scans/{sid}/retry-extraction", TARA, headers=_key()).status_code == 202
    await _run(pool, owner_sql, database)
    assert owner_sql(status, (sid,)) == [("retake_required",)]  # 3 attempts used
    _problem(api.post(f"/scans/{sid}/retry-extraction", TARA, headers=_key()), 409, "invalid-state")


async def test_a_discarded_scan_is_not_extracted(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
) -> None:
    sid = _confirmed(api, unit)["scan_id"]
    assert api.post(f"/scans/{sid}/discard", TARA).status_code == 204
    calls = ai["calls"]
    await _run(pool, owner_sql, database)
    assert ai["calls"] == calls
    assert owner_sql("SELECT status FROM extraction_attempt WHERE scan_id = %s", (sid,)) == [
        ("failed",)
    ]
