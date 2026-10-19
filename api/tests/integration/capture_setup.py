"""Shared setup for the capture tests: a unit ready for scanning, fake photo storage."""

import base64
import hashlib
import uuid
from typing import TYPE_CHECKING, Any

import pytest
from pydantic import SecretStr

from app.core import storage

if TYPE_CHECKING:
    from tests.integration.conftest import Api
from tests.integration.helpers import DANA, ERIN, TARA, TENANT_A

JPEG = b"\xff\xd8\xff\xe0" + b"pixorex-test-photo" * 10
STORE = storage.StorageConfig(
    internal_url="http://minio:9000",
    public_url="http://localhost:9000",
    access_key="k",
    secret_key=SecretStr("s"),
    bucket="pixorex",
)


def _id() -> str:
    return str(uuid.uuid4())


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _digest(body: bytes) -> str:
    return "sha-256=:" + base64.b64encode(hashlib.sha256(body).digest()).decode() + ":"


@pytest.fixture
def uploads(api: "Api", monkeypatch: pytest.MonkeyPatch) -> dict[str, bytes]:
    """Stands in for MinIO."""
    files: dict[str, bytes] = {}

    async def put(config: Any, key: str, body: bytes, content_type: str) -> None:
        files[key] = body

    monkeypatch.setattr(storage, "put", put)
    api.client.app.state.storage = STORE  # type: ignore[attr-defined]
    return files


@pytest.fixture
def unit(api: "Api", owner_sql: Any) -> dict[str, str]:
    """A new unit with a published tree (Plant > Building A > Bin 14), a published type with
    one field and its contract, Tara and Dana as its technicians."""
    bu = api.post(
        "/business-units",
        ERIN,
        headers={"Idempotency-Key": _id()},
        json={
            "name": f"Plant {uuid.uuid4().hex[:6]}",
            "facility_name": "Akron",
            "bu_admin": {"invite_email": f"{uuid.uuid4().hex[:6]}@example.com"},
        },
    ).json()["bu_id"]
    version = owner_sql("SELECT id FROM location_hierarchy_version WHERE bu_id = %s", (bu,))[0][0]
    ids = {
        k: _id() for k in ("l1", "l2", "l3", "top", "bldg", "bin", "type", "tv", "fd", "fd2", "c")
    }
    for key, name, order in (("l1", "Facility", 1), ("l2", "Building", 2), ("l3", "Bin", 3)):
        owner_sql(
            "INSERT INTO location_level_rule (id, tenant_id, version_id, level_name, level_order,"
            " requirement) VALUES (%s, %s, %s, %s, %s, 'required')",
            (ids[key], TENANT_A, version, name, order),
        )
    parent = None
    for key, level, name in (
        ("top", "l1", "Akron"),
        ("bldg", "l2", "Building A"),
        ("bin", "l3", "Bin 14"),
    ):
        owner_sql(
            "INSERT INTO location_node (id, tenant_id, version_id, level_rule_id, parent_id, name,"
            " path) VALUES (%s, %s, %s, %s, %s, %s, %s)",
            (ids[key], TENANT_A, version, ids[level], parent, name, f"/{ids[key]}"),
        )
        parent = ids[key]
    owner_sql(
        "UPDATE location_hierarchy_version SET status = 'published', tree_snapshot = '{}',"
        " published_at = now(), published_by = %s WHERE id = %s",
        (ERIN, version),
    )
    process = owner_sql("SELECT id FROM business_process WHERE bu_id = %s", (bu,))[0][0]
    owner_sql(
        "INSERT INTO equipment_type (id, tenant_id, bu_id, process_id, name, created_via, status)"
        " VALUES (%s, %s, %s, %s, 'Motor', 'blank', 'not_published')",
        (ids["type"], TENANT_A, bu, process),
    )
    owner_sql(
        "INSERT INTO equipment_type_version (id, tenant_id, equipment_type_id) VALUES (%s, %s, %s)",
        (ids["tv"], TENANT_A, ids["type"]),
    )
    owner_sql(
        "INSERT INTO field_definition (id, tenant_id, type_version_id, field_key, label,"
        " data_type, is_required, sort_order) VALUES (%s, %s, %s, 'serial', 'Serial', 'text',"
        " true, 1)",
        (ids["fd"], TENANT_A, ids["tv"]),
    )
    owner_sql(
        "INSERT INTO field_definition (id, tenant_id, type_version_id, field_key, label,"
        " data_type, is_required, sort_order) VALUES (%s, %s, %s, 'voltage', 'Voltage', 'text',"
        " false, 2)",
        (ids["fd2"], TENANT_A, ids["tv"]),
    )
    owner_sql(  # published after its fields are added: fields lock on publish
        "UPDATE equipment_type_version SET published_by = %s, published_at = now() WHERE id = %s",
        (ERIN, ids["tv"]),
    )
    owner_sql("UPDATE equipment_type SET status = 'published' WHERE id = %s", (ids["type"],))
    prompt = owner_sql("SELECT id FROM prompt_version ORDER BY created_at DESC LIMIT 1")
    if not prompt:
        prompt = owner_sql(
            "INSERT INTO prompt_version (model_name, instructions) VALUES ('test', 'test')"
            " RETURNING id"
        )
    owner_sql(
        "INSERT INTO extraction_contract (id, tenant_id, type_version_id, prompt_version_id)"
        " VALUES (%s, %s, %s, %s)",
        (ids["c"], TENANT_A, ids["tv"], prompt[0][0]),
    )
    for user in (TARA, DANA):
        owner_sql(
            "INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role)"
            " VALUES (%s, %s, %s, 'field_technician')",
            (TENANT_A, user, bu),
        )
    return {"bu": bu, **ids}


def _body(unit: dict[str, str], **extra: Any) -> dict[str, Any]:
    return {
        "client_capture_id": _id(),
        "equipment_type_id": unit["type"],
        "location_node_id": unit["bin"],
        "photo_count": 2,
        "captured_at": "2026-10-19T09:30:00Z",
        **extra,
    }


def _create(api: "Api", unit: dict[str, str], body: dict[str, Any], user: str = TARA) -> Any:
    return api.post(
        f"/business-units/{unit['bu']}/scans",
        user,
        headers={"Idempotency-Key": body["client_capture_id"]},
        json=body,
    )


def _quota(owner_sql: Any, bu: str) -> int:
    rows = owner_sql("SELECT scans_used FROM quota_usage WHERE bu_id = %s", (bu,))
    return int(rows[0][0]) if rows else 0


def _put(
    api: "Api", scan_id: str, no: int, body: bytes = JPEG, user: str = TARA, **headers: str
) -> Any:
    return api.put(
        f"/scans/{scan_id}/photos/{no}",
        user,
        content=body,
        headers={"Content-Type": "image/jpeg", "Content-Digest": _digest(body), **headers},
    )


def _confirmed(api: "Api", unit: dict[str, str]) -> dict[str, Any]:
    """A scan with photo 1 sent and its upload confirmed (attempt 1 queued)."""
    scan = _create(api, unit, _body(unit)).json()
    assert _put(api, scan["scan_id"], 1).status_code == 204
    assert api.post(f"/scans/{scan['scan_id']}/upload-complete", TARA).status_code == 202
    return scan


def _attempt_ends(owner_sql: Any, scan_id: str, status: str, processing: str) -> None:
    """What the AI proxy job will do: finish the latest attempt and move the scan on."""
    owner_sql(
        "UPDATE extraction_attempt SET status = %s WHERE scan_id = %s AND attempt_no ="
        " (SELECT max(attempt_no) FROM extraction_attempt WHERE scan_id = %s)",
        (status, scan_id, scan_id),
    )
    owner_sql("UPDATE scan SET processing_status = %s WHERE id = %s", (processing, scan_id))


def _key() -> dict[str, str]:
    return {"Idempotency-Key": _id()}
