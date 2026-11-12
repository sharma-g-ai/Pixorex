"""The worker's AI extraction (FR-4.4-4.9): from upload-complete to ready_to_review."""

import asyncio
from typing import Any, Literal

import pytest

from app.core import storage
from app.repositories.scans import EXTRACTION_EVENT
from app.services import ai_proxy
from app.workers import outbox, runner
from app.workers.settings import WorkerSettings
from tests.integration.capture_setup import JPEG, _confirmed, _key, _problem
from tests.integration.conftest import Api
from tests.integration.helpers import TARA


def _settings(database: dict[str, str], role: str = "all", **extra: Any) -> WorkerSettings:
    return WorkerSettings(  # type: ignore[call-arg]
        worker_database_url=database["worker"],
        worker_role=role,
        minio_access_key="k",
        minio_secret_key="s",  # noqa: S106  (test value)
        openai_api_key="sk-test",
        **extra,
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


async def _run(pool: Any, owner_sql: Any, database: dict[str, str], role: str = "all") -> None:
    # In a thread: with a worker mid-call, this UPDATE may have to wait for a row lock, and
    # waiting on the event loop would stop that worker from ever finishing.
    await asyncio.to_thread(
        owner_sql,
        "UPDATE outbox_event SET next_run_at = now() - interval '1 second'"
        " WHERE status = 'pending'",
    )

    async def no_mail(settings: Any, **_: str) -> None:
        return None

    await outbox.run_due(pool, _settings(database, role), send=no_mail, limit=1000)


async def test_only_the_extraction_worker_reads_scans(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
) -> None:
    """GIVEN an uploaded scan WHEN the general worker runs THEN the scan still waits;
    WHEN the extraction worker runs THEN it is ready to review."""
    sid = _confirmed(api, unit)["scan_id"]
    await _run(pool, owner_sql, database, role="general")
    assert ai["calls"] == 0
    assert api.get(f"/scans/{sid}", TARA).json()["processing_status"] == "extracting"
    await _run(pool, owner_sql, database, role="extraction")
    assert api.get(f"/scans/{sid}", TARA).json()["processing_status"] == "ready_to_review"


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


def _event(owner_sql: Any, scan_id: str) -> tuple[str, int, bool]:
    """(status, tries counted, due later) of the event for the scan's latest attempt."""
    return owner_sql(
        "SELECT e.status, e.attempts, e.next_run_at > now() FROM outbox_event e"
        " JOIN extraction_attempt a ON a.id::text = e.payload->>'attempt_id'"
        " WHERE a.scan_id = %s ORDER BY a.attempt_no DESC LIMIT 1",
        (scan_id,),
    )[0]


async def _always_unexpected(config: Any, key: str) -> bytes:
    """Photo storage failing with an error that is not on the outbox's retry list."""
    raise ValueError("not an error the outbox knows")


async def test_an_unexpected_error_does_not_hold_up_the_scan_behind_it(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN a scan whose extraction hits an error the outbox does not know, and a second scan
    WHEN the worker runs THEN the second is ready to review and the first waits for a retry
    with one try counted; WHEN the error clears THEN the retry extracts the first."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    broken, fine = (_confirmed(api, unit)["scan_id"] for _ in range(2))

    async def get(config: Any, key: str) -> bytes:
        if broken in key:  # the object key holds the scan id
            return await _always_unexpected(config, key)
        return JPEG

    monkeypatch.setattr(storage, "get", get)
    await _run(pool, owner_sql, database)
    status = "SELECT processing_status FROM scan WHERE id = %s"
    assert owner_sql(status, (fine,)) == [("ready_to_review",)]
    assert owner_sql(status, (broken,)) == [("extracting",)]
    assert _event(owner_sql, broken) == ("pending", 1, True)

    async def healthy(config: Any, key: str) -> bytes:
        return JPEG

    monkeypatch.setattr(storage, "get", healthy)
    await _run(pool, owner_sql, database)
    assert owner_sql(status, (broken,)) == [("ready_to_review",)]


async def test_an_error_that_keeps_happening_fails_the_attempt(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN an extraction that always hits an error the outbox does not know WHEN the worker
    has tried as often as the outbox allows THEN the event, the attempt and the scan are failed,
    so the technician can retry instead of waiting on an extracting scan."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sid = _confirmed(api, unit)["scan_id"]
    monkeypatch.setattr(storage, "get", _always_unexpected)
    for _ in range(outbox.MAX_ATTEMPTS):
        await _run(pool, owner_sql, database)
    assert _event(owner_sql, sid)[:2] == ("failed", outbox.MAX_ATTEMPTS)
    assert owner_sql("SELECT status FROM extraction_attempt WHERE scan_id = %s", (sid,)) == [
        ("failed",)
    ]
    assert owner_sql("SELECT processing_status FROM scan WHERE id = %s", (sid,)) == [("failed",)]


async def test_a_failing_clean_up_does_not_keep_the_event_alive(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN an extraction that always errors and a clean-up that errors as well WHEN the outbox
    gives up on the event THEN the event is failed for good and the worker carries on."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sid = _confirmed(api, unit)["scan_id"]

    async def broken_clean_up(conn: Any, event: Any) -> None:
        raise RuntimeError("the clean-up failed too")

    monkeypatch.setattr(storage, "get", _always_unexpected)
    monkeypatch.setitem(outbox.ON_GIVE_UP, EXTRACTION_EVENT, broken_clean_up)
    for _ in range(outbox.MAX_ATTEMPTS):
        await _run(pool, owner_sql, database)
    assert _event(owner_sql, sid)[:2] == ("failed", outbox.MAX_ATTEMPTS)


@pytest.mark.parametrize(
    ("answer", "outcome"),
    [
        (None, "succeeded"),
        (TimeoutError("slow"), "timed_out"),
        (ai_proxy.AiUnavailableError("down"), "failed"),
    ],
)
async def test_each_extraction_logs_its_wait_and_its_ai_time(
    answer: Exception | None,
    outcome: str,
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    caplog: pytest.LogCaptureFixture,
) -> None:
    """GIVEN a confirmed scan WHEN the worker extracts it THEN one log line gives the time the
    scan waited and the time the AI call took, and carries nothing from the scan."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    _confirmed(api, unit)
    ai["outcome"] = answer
    caplog.set_level("INFO")
    caplog.clear()
    await _run(pool, owner_sql, database)
    lines = [r.msg for r in caplog.records if isinstance(r.msg, dict)]  # structlog event dicts
    [line] = [m for m in lines if m.get("event") == "extraction_timing"]
    assert (line["outcome"], line["attempt_no"]) == (outcome, 1)
    assert isinstance(line["queue_wait_ms"], int) and line["queue_wait_ms"] >= 0
    assert isinstance(line["provider_ms"], int) and line["provider_ms"] >= 0
    # every log line also gets "level" and "timestamp"; the rest is numbers and the outcome
    assert set(line) - {"event", "level", "timestamp"} == {
        "outcome",
        "attempt_no",
        "queue_wait_ms",
        "provider_ms",
    }


async def _no_mail(settings: Any, **_: str) -> None:
    return None


class Gate:
    """A stand-in for the AI call that can be held open, and counts the calls open at once."""

    def __init__(
        self, answer: Any, hold: Literal["all", "first", "none"], delay: float = 0.0
    ) -> None:
        self.answer, self.hold, self.delay = answer, hold, delay  # answer: the `ai` fixture's fake
        self.started, self.release = asyncio.Event(), asyncio.Event()
        self.calls = self.open = self.most_open = 0

    async def extract(self, http: Any, config: Any, **kwargs: Any) -> ai_proxy.Extraction:
        self.calls += 1
        held = self.hold == "all" or (self.hold == "first" and self.calls == 1)
        self.open += 1
        self.most_open = max(self.most_open, self.open)
        self.started.set()
        try:
            await (self.release.wait() if held else asyncio.sleep(self.delay))
        finally:
            self.open -= 1
        return await self.answer(http, config, **kwargs)  # type: ignore[no-any-return]


_VALUES = (
    "SELECT count(*) FROM ai_field_value v JOIN extraction_attempt a ON a.id = v.attempt_id"
    " WHERE a.scan_id = %s"
)
_STATUS = "SELECT processing_status FROM scan WHERE id = %s"


async def test_a_discard_does_not_wait_for_an_ai_call_in_progress(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN an AI call in progress WHEN the technician discards the scan THEN the discard
    answers at once, and when the call ends it saves no values."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sid = _confirmed(api, unit)["scan_id"]
    gate = Gate(ai_proxy.extract, hold="all")
    monkeypatch.setattr(ai_proxy, "extract", gate.extract)
    worker = asyncio.create_task(_run(pool, owner_sql, database))
    try:
        await asyncio.wait_for(gate.started.wait(), 5)
        discard = asyncio.to_thread(api.post, f"/scans/{sid}/discard", TARA)
        assert (await asyncio.wait_for(discard, 3)).status_code == 204
    finally:
        gate.release.set()
        await worker
    attempt = "SELECT status FROM extraction_attempt WHERE scan_id = %s"
    assert owner_sql(attempt, (sid,)) == [("failed",)]
    assert owner_sql(_VALUES, (sid,)) == [(0,)]


async def test_a_repeated_upload_complete_is_answered_while_the_ai_call_runs(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN an AI call in progress WHEN the phone repeats upload-complete THEN it gets the same
    202 at once, not a wait followed by a 409."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sid = _confirmed(api, unit)["scan_id"]
    gate = Gate(ai_proxy.extract, hold="all")
    monkeypatch.setattr(ai_proxy, "extract", gate.extract)
    worker = asyncio.create_task(_run(pool, owner_sql, database))
    try:
        await asyncio.wait_for(gate.started.wait(), 5)
        again = asyncio.to_thread(api.post, f"/scans/{sid}/upload-complete", TARA)
        answer = await asyncio.wait_for(again, 3)
        assert (answer.status_code, answer.json()["attempt_no"]) == (202, 1)
    finally:
        gate.release.set()
        await worker
    assert owner_sql(_STATUS, (sid,)) == [("ready_to_review",)]


class _Crash(BaseException):
    """A worker killed in the middle of an AI call: nothing after the call runs."""


async def test_an_event_whose_worker_died_is_taken_again_when_its_lease_ends(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN a worker that dies in the middle of an AI call WHEN its lease has not ended THEN
    no other worker takes the event and no failure is counted; WHEN the lease has ended THEN
    the next worker extracts the scan."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sid = _confirmed(api, unit)["scan_id"]
    healthy = ai_proxy.extract

    async def dies(http: Any, config: Any, **kwargs: Any) -> ai_proxy.Extraction:
        raise _Crash

    monkeypatch.setattr(ai_proxy, "extract", dies)
    with pytest.raises(_Crash):
        await _run(pool, owner_sql, database)
    assert _event(owner_sql, sid) == ("pending", 0, True)  # leased: due later, no try counted

    monkeypatch.setattr(ai_proxy, "extract", healthy)
    other = _settings(database, "extraction")
    assert await outbox.run_due(pool, other, send=_no_mail, limit=1000) == 0
    assert owner_sql(_STATUS, (sid,)) == [("extracting",)]

    await _run(pool, owner_sql, database)  # makes every pending event due: the lease has ended
    assert owner_sql(_STATUS, (sid,)) == [("ready_to_review",)]


async def test_when_a_lease_runs_out_only_the_first_result_is_saved(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN an AI call that outlasts its lease, and a second worker that extracts the scan
    meanwhile WHEN the first call ends THEN its result is not saved a second time."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sid = _confirmed(api, unit)["scan_id"]
    gate = Gate(ai_proxy.extract, hold="first")
    monkeypatch.setattr(ai_proxy, "extract", gate.extract)
    first = asyncio.create_task(_run(pool, owner_sql, database))
    try:
        await asyncio.wait_for(gate.started.wait(), 5)
        await asyncio.wait_for(_run(pool, owner_sql, database), 10)  # the lease has ended
        assert owner_sql(_STATUS, (sid,)) == [("ready_to_review",)]
    finally:
        gate.release.set()
        await first
    assert owner_sql(_VALUES, (sid,)) == [(2,)]  # the type has two fields; saved once
    assert owner_sql("SELECT status FROM extraction_attempt WHERE scan_id = %s", (sid,)) == [
        ("succeeded",)
    ]
    assert gate.calls == 2


async def test_a_worker_told_to_stop_takes_no_more_events(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
) -> None:
    """GIVEN a scan waiting WHEN the worker is told to stop THEN it takes no more events;
    WHEN it is not told to stop THEN it extracts the scan."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sid = _confirmed(api, unit)["scan_id"]
    stop = asyncio.Event()
    stop.set()
    worker = _settings(database, "extraction")
    assert await outbox.run_due(pool, worker, send=_no_mail, stop=stop) == 0
    assert owner_sql(_STATUS, (sid,)) == [("extracting",)]
    assert await outbox.run_due(pool, worker, send=_no_mail) >= 1
    assert owner_sql(_STATUS, (sid,)) == [("ready_to_review",)]


async def test_the_extraction_container_makes_several_ai_calls_at_once(
    api: Api,
    owner_sql: Any,
    unit: dict[str, str],
    uploads: dict[str, bytes],
    pool: Any,
    database: dict[str, str],
    ai: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """GIVEN ten scans waiting and a concurrency of 3 WHEN the claim loops run THEN no more than
    3 AI calls are open at once, and every scan is extracted once."""
    await _run(pool, owner_sql, database)  # extract what other tests left waiting
    sids = [_confirmed(api, unit)["scan_id"] for _ in range(10)]
    gate = Gate(ai_proxy.extract, hold="none", delay=0.05)
    monkeypatch.setattr(ai_proxy, "extract", gate.extract)
    settings = _settings(database, "extraction", extraction_concurrency=3, worker_tick_s=0.05)
    stop = asyncio.Event()
    loops = asyncio.create_task(runner.run_claim_loops(pool, settings, stop))
    ready = 0
    try:
        for _ in range(200):
            ready = owner_sql(
                "SELECT count(*) FROM scan WHERE id = ANY(%s::uuid[])"
                " AND processing_status = 'ready_to_review'",
                (sids,),
            )[0][0]
            if ready == len(sids):
                break
            await asyncio.sleep(0.05)
    finally:
        stop.set()
        await asyncio.wait_for(loops, 10)
    assert ready == len(sids)
    assert (gate.most_open, gate.calls) == (3, 10)
