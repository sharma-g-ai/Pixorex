"""Exports over 1,000 rows: the worker builds the file, the requester gets a 1-hour link."""

import uuid
from typing import Any
from urllib.parse import parse_qs, urlparse

import pytest
from pydantic import SecretStr

from app.core import storage
from app.workers import outbox
from app.workers.settings import WorkerSettings
from tests.integration.conftest import Api
from tests.integration.helpers import BO, ERIN, TENANT_A
from tests.integration.test_s2_identity import P04, P05

STORE = storage.StorageConfig(
    internal_url="http://minio:9000",
    public_url="http://localhost:9000",
    access_key="test-key",
    secret_key=SecretStr("test-secret"),
    bucket="pixorex",
)


@pytest.fixture
def uploads(monkeypatch: pytest.MonkeyPatch) -> dict[str, bytes]:
    """Stands in for MinIO: keeps what the worker uploads."""
    files: dict[str, bytes] = {}

    async def put(config: Any, key: str, body: bytes, content_type: str) -> None:
        files[key] = body

    async def ensure_bucket(config: Any) -> None:
        return None

    monkeypatch.setattr(storage, "put", put)
    monkeypatch.setattr(storage, "ensure_bucket", ensure_bucket)
    return files


def _settings(database: dict[str, str], *, with_storage: bool = True) -> WorkerSettings:
    keys: dict[str, Any] = (
        {"minio_access_key": "test-key", "minio_secret_key": "test-secret"} if with_storage else {}
    )
    return WorkerSettings(worker_database_url=database["worker"], **keys)  # type: ignore[arg-type]


async def _no_mail(settings: Any, **_: str) -> None:
    return None


def _make_due(owner_sql: Any) -> None:
    owner_sql(
        "UPDATE outbox_event SET next_run_at = now() - interval '1 second' WHERE status = 'pending'"
    )


def _rows_for(owner_sql: Any, category: str, unit: str = P04) -> None:
    owner_sql(
        "INSERT INTO audit_log (tenant_id, bu_id, actor_type, category, action, summary)"
        " SELECT %s, %s, 'system', %s, 'bulk', 'row ' || g FROM generate_series(1, 1001) g",
        (TENANT_A, unit, category),
    )


def _queue(api: Api, user: str, **filters: Any) -> dict[str, Any]:
    response = api.post(
        "/exports",
        user,
        headers={"Idempotency-Key": str(uuid.uuid4())},
        json={"export_kind": "audit_log", "filters": filters},
    )
    assert response.status_code == 202, response.text
    job: dict[str, Any] = response.json()
    return job


def _job(owner_sql: Any, export_id: str) -> tuple[Any, ...]:
    return tuple(
        owner_sql(
            "SELECT status, file_key, row_count, link_expires_at > now() + interval '55 minutes'"
            " FROM export_job WHERE id = %s",
            (export_id,),
        )[0]
    )


async def test_the_worker_builds_the_file_and_the_requester_gets_a_signed_link(
    pool: Any, api: Api, owner_sql: Any, database: dict[str, str], uploads: dict[str, bytes]
) -> None:
    _rows_for(owner_sql, "retention")
    job = _queue(api, ERIN, category="retention")
    _make_due(owner_sql)
    await outbox.run_due(pool, _settings(database), send=_no_mail, limit=1000)
    status, key, rows, an_hour = _job(owner_sql, job["export_id"])
    assert (status, key, an_hour) == ("ready", f"exports/{TENANT_A}/{job['export_id']}.csv", True)
    lines = uploads[key].decode().splitlines()
    assert lines[0].startswith("When,Who,Unit,Category") and len(lines) == rows + 1 >= 1002
    told = owner_sql(
        "SELECT count(*) FROM notification WHERE kind = 'export_ready' AND object_id = %s"
        " AND recipient_user_id = %s",
        (job["export_id"], ERIN),
    )
    assert told[0][0] == 1

    api.client.app.state.storage = STORE  # type: ignore[attr-defined]
    got = api.get(f"/exports/{job['export_id']}", ERIN).json()
    assert got["status"] == "ready" and got["row_count"] == rows
    link = urlparse(got["download_url"])
    query = parse_qs(link.query)
    assert (link.netloc, link.path) == ("localhost:9000", f"/pixorex/{key}")
    assert int(query["X-Amz-Expires"][0]) <= 3600
    assert "attachment" in query["response-content-disposition"][0]

    owner_sql(
        "UPDATE export_job SET link_expires_at = now() - interval '1 second' WHERE id = %s",
        (job["export_id"],),
    )
    expired = api.get(f"/exports/{job['export_id']}", ERIN)
    assert expired.status_code == 409 and expired.json()["type"] == "/problems/link-expired"


async def test_a_bu_admins_job_is_theirs_and_rechecked_at_build_time(
    pool: Any, api: Api, owner_sql: Any, database: dict[str, str], uploads: dict[str, bytes]
) -> None:
    _rows_for(owner_sql, "users")
    job = _queue(api, BO, category="users")  # no unit picked: the unit they run
    assert owner_sql("SELECT bu_id::text FROM export_job WHERE id = %s", (job["export_id"],)) == [
        (P04,)
    ]
    assert api.get(f"/exports/{job['export_id']}", BO).json()["status"] == "queued"
    # Before the worker gets to it, the filter points at a unit Bo doesn't run.
    owner_sql(
        "UPDATE export_job SET filters_json = filters_json || jsonb_build_object('bu_id', %s::text)"
        " WHERE id = %s",
        (P05, job["export_id"]),
    )
    _make_due(owner_sql)
    await outbox.run_due(pool, _settings(database), send=_no_mail, limit=1000)
    assert _job(owner_sql, job["export_id"])[:2] == ("failed", None)
    assert not [k for k in uploads if job["export_id"] in k]


async def test_without_storage_the_job_fails_after_the_last_try(
    pool: Any, api: Api, owner_sql: Any, database: dict[str, str]
) -> None:
    _rows_for(owner_sql, "locations")
    job = _queue(api, ERIN, category="locations")
    for _ in range(outbox.MAX_ATTEMPTS):
        _make_due(owner_sql)
        await outbox.run_due(
            pool, _settings(database, with_storage=False), send=_no_mail, limit=1000
        )
    assert _job(owner_sql, job["export_id"])[0] == "failed"
    got = api.get(f"/exports/{job['export_id']}", ERIN).json()
    assert (got["status"], got["download_url"]) == ("failed", None)
