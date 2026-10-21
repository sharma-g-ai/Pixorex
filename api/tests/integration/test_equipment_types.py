"""Contracts 2.10-2.20 against PostgreSQL: drafts, fields, copy, AI assist, publish, freeze."""

import uuid
from typing import Any

from tests.integration.conftest import Api
from tests.integration.helpers import BO, DANA, ERIN, TARA
from tests.integration.test_s2_identity import P04, P05

PUMP_FIELDS = [
    {"label": "Serial number", "data_type": "text", "is_required": True, "is_critical": True},
    {"label": "Voltage", "data_type": "number", "is_required": False, "is_critical": False},
]


def _key() -> dict[str, str]:
    return {"Idempotency-Key": str(uuid.uuid4())}


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _name() -> str:
    return f"Pump {uuid.uuid4().hex[:6]}"


def _create(api: Api, user: str = BO, bu: str = P04, **body: Any) -> Any:
    return api.post(
        f"/business-units/{bu}/equipment-types",
        user,
        headers=_key(),
        json={"name": _name(), "created_via": "blank", **body},
    )


def _type_with_fields(api: Api) -> dict[str, Any]:
    created = _create(api).json()
    for field in PUMP_FIELDS:
        api.post(f"/equipment-types/{created['type_id']}/fields", BO, headers=_key(), json=field)
    return api.get(f"/equipment-types/{created['type_id']}", BO).json()


def test_create_a_blank_draft(api: Api) -> None:
    created = _create(api)
    assert created.status_code == 201, created.text
    body = created.json()
    assert (body["status"], body["version_no"], body["field_count"], body["fields"]) == (
        "not_published",
        1,
        0,
        [],
    )
    _problem(
        api.post(
            f"/business-units/{P04}/equipment-types",
            BO,
            headers=_key(),
            json={"name": body["name"], "created_via": "blank"},
        ),
        409,
        "duplicate-name",
    )
    _problem(_create(api, user=ERIN), 403, "forbidden")  # x-roles: bu_admin only
    _problem(_create(api, user=DANA), 403, "forbidden")  # runs Plant 05, not Plant 04
    _problem(_create(api, fields=PUMP_FIELDS), 400, "validation")  # fields only with AI assist


def test_fields_rules(api: Api) -> None:
    type_id = _create(api).json()["type_id"]
    added = api.post(f"/equipment-types/{type_id}/fields", BO, headers=_key(), json=PUMP_FIELDS[0])
    assert added.status_code == 201, added.text
    assert (added.json()["field_key"], added.json()["origin"], added.json()["sort_order"]) == (
        "serial_number",
        "manual",
        1,
    )
    assert added.json()["flag_below_confidence"] == 0.85
    _problem(
        api.post(f"/equipment-types/{type_id}/fields", BO, headers=_key(), json=PUMP_FIELDS[0]),
        409,
        "duplicate-name",
    )
    one_choice = {
        "label": "Phase",
        "data_type": "dropdown",
        "options": ["1"],
        "is_required": False,
        "is_critical": False,
    }
    _problem(
        api.post(f"/equipment-types/{type_id}/fields", BO, headers=_key(), json=one_choice),
        400,
        "validation",
    )
    dropdown = api.post(
        f"/equipment-types/{type_id}/fields",
        BO,
        headers=_key(),
        json={**one_choice, "options": ["1", "3"]},
    ).json()
    assert dropdown["options"] == ["1", "3"]

    changed = api.call(
        "PATCH",
        f"/equipment-types/{type_id}/fields/{dropdown['field_id']}",
        BO,
        json={"label": "Phase count", "data_type": "text"},
    )
    assert changed.status_code == 200, changed.text
    assert (changed.json()["field_key"], changed.json()["options"]) == ("phase_count", None)
    _problem(
        api.call("PATCH", f"/equipment-types/{type_id}/fields/{dropdown['field_id']}", BO, json={}),
        400,
        "validation",
    )

    fields = api.get(f"/equipment-types/{type_id}", BO).json()["fields"]
    ids = [f["field_id"] for f in fields]
    _problem(
        api.put(f"/equipment-types/{type_id}/field-order", BO, json={"field_ids": ids[:1]}),
        400,
        "validation",
    )
    reordered = api.put(
        f"/equipment-types/{type_id}/field-order", BO, json={"field_ids": list(reversed(ids))}
    )
    assert [f["field_id"] for f in reordered.json()["fields"]] == list(reversed(ids))
    assert api.call("DELETE", f"/equipment-types/{type_id}/fields/{ids[0]}", BO).status_code == 204
    assert api.get(f"/equipment-types/{type_id}", BO).json()["field_count"] == len(ids) - 1


def test_copy_and_ai_assist(api: Api) -> None:
    source = _type_with_fields(api)
    copy = _create(api, created_via="copy", copied_from_type_id=source["type_id"])
    assert copy.status_code == 201, copy.text
    assert [f["label"] for f in copy.json()["fields"]] == ["Serial number", "Voltage"]
    assert copy.json()["copied_from_type_id"] == source["type_id"]
    _problem(_create(api, created_via="copy"), 400, "validation")
    other_unit = api.post(
        f"/business-units/{P05}/equipment-types",
        DANA,
        headers=_key(),
        json={"name": _name(), "created_via": "blank"},
    ).json()
    _problem(
        _create(api, created_via="copy", copied_from_type_id=other_unit["type_id"]),
        400,
        "validation",
    )
    assisted = _create(api, created_via="ai_assist", fields=PUMP_FIELDS)
    assert {f["origin"] for f in assisted.json()["fields"]} == {"ai_suggested"}


def test_publish_freezes_the_type(api: Api, owner_sql: Any) -> None:
    empty = _create(api).json()
    _problem(api.post(f"/equipment-types/{empty['type_id']}/publish", BO), 409, "no-fields")
    draft = _type_with_fields(api)
    type_id = draft["type_id"]
    published = api.post(f"/equipment-types/{type_id}/publish", BO)
    assert published.status_code == 200, published.text
    assert published.json()["status"] == "published"
    contract = owner_sql(
        "SELECT status FROM extraction_contract WHERE id = %s", (published.json()["contract_id"],)
    )
    assert contract[0][0] == "active"
    _problem(
        api.call("PATCH", f"/equipment-types/{type_id}", BO, json={"name": "New"}),
        409,
        "locked-after-publish",
    )
    _problem(
        api.post(f"/equipment-types/{type_id}/fields", BO, headers=_key(), json=PUMP_FIELDS[0]),
        409,
        "locked-after-publish",
    )
    _problem(api.call("DELETE", f"/equipment-types/{type_id}", BO), 409, "locked-after-publish")
    _problem(api.post(f"/equipment-types/{type_id}/publish", BO), 409, "locked-after-publish")
    after = api.get(f"/equipment-types/{type_id}", BO).json()
    assert after["status"] == "published" and after["published_at"]


def test_technicians_see_only_published_types(api: Api) -> None:
    draft = _create(api).json()
    published = _type_with_fields(api)
    api.post(f"/equipment-types/{published['type_id']}/publish", BO)
    mine = {
        t["type_id"]
        for t in api.get(f"/business-units/{P04}/equipment-types?limit=100", BO).json()["items"]
    }
    assert {draft["type_id"], published["type_id"]} <= mine
    theirs = api.get(
        f"/business-units/{P04}/equipment-types?limit=100&include=fields", TARA
    ).json()["items"]
    assert draft["type_id"] not in {t["type_id"] for t in theirs}
    listed = next(t for t in theirs if t["type_id"] == published["type_id"])
    assert [f["label"] for f in listed["fields"]] == ["Serial number", "Voltage"]
    _problem(api.get(f"/equipment-types/{draft['type_id']}", TARA), 404, "not-found")
    assert api.get(f"/equipment-types/{published['type_id']}", TARA).status_code == 200
    _problem(api.get(f"/business-units/{P05}/equipment-types", TARA), 403, "forbidden")


def test_rename_delete_and_ai_suggest(api: Api, owner_sql: Any) -> None:
    created = _create(api).json()
    renamed = api.call(
        "PATCH", f"/equipment-types/{created['type_id']}", BO, json={"name": "  Gear   box "}
    )
    assert renamed.json()["name"] == "Gear box"
    assert api.call("DELETE", f"/equipment-types/{created['type_id']}", BO).status_code == 204
    _problem(api.get(f"/equipment-types/{created['type_id']}", BO), 404, "not-found")
    audit = owner_sql(
        "SELECT count(*) FROM audit_log WHERE object_id = %s AND category = 'equipment_types'",
        (created["type_id"],),
    )
    assert audit[0][0] == 3  # created, renamed, deleted


def test_null_for_a_required_setting_is_a_400_not_a_crash(api: Api) -> None:
    created = _type_with_fields(api)
    field_id = created["fields"][0]["field_id"]
    for body in ({"is_required": None}, {"label": None}, {"data_type": None}):
        _problem(
            api.call(
                "PATCH", f"/equipment-types/{created['type_id']}/fields/{field_id}", BO, json=body
            ),
            400,
            "validation",
        )


PNG = b"\x89PNG\r\n\x1a\n" + b"label" * 10


def _suggest(api: Api, user: str, image: bytes = PNG, name: str = "Motor") -> Any:
    return api.post(
        f"/business-units/{P04}/equipment-types/ai-suggest",
        user,
        data={"name": name},
        files={"image": ("label.png", image, "image/png")},
    )


def test_ai_assist_suggests_fields_from_a_photo(api: Api) -> None:
    """Contract 2.20 through the AI proxy (Portkey, faked here); nothing is saved."""
    import httpx
    from pydantic import SecretStr

    from app.services.ai_proxy import AiConfig

    app: Any = api.client.app
    _problem(_suggest(api, BO), 503, "ai-unavailable")  # no Portkey key configured
    sent: list[httpx.Request] = []

    def portkey(request: httpx.Request) -> httpx.Response:
        sent.append(request)
        content = '{"fields": [{"label": "Serial number", "data_type": "text"}]}'
        return httpx.Response(200, json={"choices": [{"message": {"content": content}}]})

    app.state.ai = AiConfig(
        url="https://portkey.test/v1", api_key=SecretStr("k"), config_id="pc", timeout_s=5
    )
    real_http = app.state.http
    app.state.http = httpx.AsyncClient(transport=httpx.MockTransport(portkey))
    try:
        answer = _suggest(api, BO)
        assert answer.status_code == 200, answer.text
        assert answer.json() == {
            "suggested_fields": [{"label": "Serial number", "data_type": "text"}]
        }
        assert len(sent) == 1
        _problem(_suggest(api, TARA), 403, "forbidden")  # not a BU Admin of the unit
        _problem(_suggest(api, BO, image=b"GIF89a not a label"), 400, "validation")
        _problem(_suggest(api, BO, name="   "), 400, "validation")
        big = PNG + b"x" * (10 * 1024 * 1024)
        _problem(_suggest(api, BO, image=big), 400, "photo-too-large")
        assert len(sent) == 1  # refused requests never reach the provider

        app.state.http = httpx.AsyncClient(
            transport=httpx.MockTransport(lambda r: httpx.Response(502, json={}))
        )
        _problem(_suggest(api, BO), 503, "ai-unavailable")  # provider failed
    finally:
        app.state.http = real_http
        app.state.ai = None
