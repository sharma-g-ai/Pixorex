"""Test scans, written directly as the owner because the capture API (the phone's, slice S3)
is not built yet. Each scan has the full chain the review screens read: a published type with
fields, a location, an AI attempt with values, a submitted revision and verdicts."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from tests.integration.helpers import TENANT_A

P04 = str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/unit/p04"))
_ids = {
    k: str(uuid.uuid5(uuid.NAMESPACE_URL, f"pixorex-test/{k}"))
    for k in (
        "level",
        "node",
        "type",
        "version",
        "f_serial",
        "f_volt",
        "f_phase",
        "prompt",
        "contract",
    )
}
FIELDS = [
    ("f_serial", "serial_number", "Serial number", True),
    ("f_volt", "voltage", "Voltage", False),
    ("f_phase", "phase", "Phase", False),
]


def _setup_once(sql: Any) -> None:
    """A level, a node, a published type with 3 fields and its contract in Plant 04."""
    if sql("SELECT 1 FROM equipment_type WHERE id = %s", (_ids["type"],)):
        return
    version = sql("SELECT id FROM location_hierarchy_version WHERE bu_id = %s", (P04,))[0][0]
    process = sql("SELECT id FROM business_process WHERE bu_id = %s AND is_default", (P04,))[0][0]
    sql(
        "INSERT INTO location_level_rule (id, tenant_id, version_id, level_name, level_order,"
        " requirement) VALUES (%s, %s, %s, 'Facility', 1, 'required') ON CONFLICT DO NOTHING",
        (_ids["level"], TENANT_A, version),
    )
    sql(
        "INSERT INTO location_node (id, tenant_id, version_id, level_rule_id, name, path)"
        " VALUES (%s, %s, %s, %s, 'Cleveland', %s) ON CONFLICT DO NOTHING",
        (_ids["node"], TENANT_A, version, _ids["level"], f"/{_ids['node']}"),
    )
    sql(
        "INSERT INTO equipment_type (id, tenant_id, bu_id, process_id, name, created_via)"
        " VALUES (%s, %s, %s, %s, 'Test Pump', 'blank')",
        (_ids["type"], TENANT_A, P04, process),
    )
    sql(
        "INSERT INTO equipment_type_version (id, tenant_id, equipment_type_id) VALUES (%s, %s, %s)",
        (_ids["version"], TENANT_A, _ids["type"]),
    )
    for order, (key, field_key, label, required) in enumerate(FIELDS, start=1):
        sql(
            "INSERT INTO field_definition (id, tenant_id, type_version_id, field_key, label,"
            " data_type, is_required, sort_order) VALUES (%s, %s, %s, %s, %s, 'text', %s, %s)",
            (_ids[key], TENANT_A, _ids["version"], field_key, label, required, order),
        )
    sql(
        "INSERT INTO prompt_version (id, model_name, instructions) VALUES (%s, 'test', 'test')"
        " ON CONFLICT DO NOTHING",
        (_ids["prompt"],),
    )
    sql("UPDATE equipment_type SET status = 'published' WHERE id = %s", (_ids["type"],))
    sql(
        "INSERT INTO extraction_contract (id, tenant_id, type_version_id, prompt_version_id)"
        " VALUES (%s, %s, %s, %s)",
        (_ids["contract"], TENANT_A, _ids["version"], _ids["prompt"]),
    )


def waiting_scan(
    sql: Any,
    technician: str,
    *,
    hours_waiting: float = 1,
    empty_required: bool = False,
    bu: str = P04,
) -> dict[str, str]:
    """A scan of Plant 04 waiting for approval. Serial is flagged (low confidence) and
    corrected; voltage accepted; phase unreadable."""
    _setup_once(sql)
    scan_id, record_no = str(uuid.uuid4()), f"REC-{uuid.uuid4().int % 10**8:08d}"
    submitted = datetime.now(UTC) - timedelta(hours=hours_waiting)
    process = sql("SELECT id FROM business_process WHERE bu_id = %s AND is_default", (bu,))[0][0]
    sql(
        "INSERT INTO scan (id, tenant_id, bu_id, process_id, record_no, client_capture_id,"
        " technician_id, equipment_type_id, contract_id, location_node_id, location_path_snapshot,"
        " processing_status, review_status, captured_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %s,"
        " %s, %s, 'Cleveland', 'ready_to_review', 'waiting_for_approval', %s)",
        (
            scan_id,
            TENANT_A,
            bu,
            process,
            record_no,
            str(uuid.uuid4()),
            technician,
            _ids["type"],
            _ids["contract"],
            _ids["node"],
            submitted - timedelta(minutes=10),
        ),
    )
    attempt = sql(
        "INSERT INTO extraction_attempt (tenant_id, scan_id, attempt_no, contract_id,"
        " trigger, status) VALUES (%s, %s, 1, %s, 'first', 'succeeded') RETURNING id",
        (TENANT_A, scan_id, _ids["contract"]),
    )[0][0]
    ai = {}
    for key, value, confidence, flags in [
        ("f_serial", "SN-1O23", 0.41, ["low_confidence"]),
        ("f_volt", "480", 0.97, []),
        ("f_phase", None, None, ["no_confidence"]),
    ]:
        ai[key] = sql(
            "INSERT INTO ai_field_value (tenant_id, attempt_id, field_definition_id, value,"
            " confidence, flag_reasons) VALUES (%s, %s, %s, %s, %s, %s) RETURNING id",
            (TENANT_A, attempt, _ids[key], value, confidence, flags),
        )[0][0]
    serial = None if empty_required else "SN-1023"
    revision = sql(
        "INSERT INTO revision (tenant_id, scan_id, revision_no, origin, values_json,"
        " empty_required_fields, submitted_by, submitted_at) VALUES (%s, %s, 1,"
        " 'technician_review', %s::jsonb, %s, %s, %s) RETURNING id",
        (
            TENANT_A,
            scan_id,
            f'{{"serial_number": "{serial or ""}", "voltage": "480"}}',
            ["serial_number"] if empty_required else [],
            technician,
            submitted,
        ),
    )[0][0]
    verdicts = [
        (
            "f_serial",
            "serial_number",
            serial,
            "left_empty" if empty_required else "corrected",
            None,
            None,
        ),
        ("f_volt", "voltage", "480", "accepted", None, None),
        ("f_phase", "phase", None, "unreadable", "label_worn", None),
    ]
    for key, field_key, value, state, reason, note in verdicts:
        sql(
            "INSERT INTO revision_field (tenant_id, revision_id, ai_field_value_id, field_key,"
            " value, verification_state, unreadable_reason, note)"
            " VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
            (TENANT_A, revision, ai[key], field_key, value, state, reason, note),
        )
    return {"scan_id": scan_id, "record_no": record_no}


def escalate(sql: Any, scan_id: str, reason: str = "not_approved_24h") -> str:
    return str(
        sql(
            "INSERT INTO escalation (tenant_id, bu_id, scan_id, reason) VALUES (%s, %s, %s, %s)"
            " RETURNING id",
            (TENANT_A, P04, scan_id, reason),
        )[0][0]
    )
