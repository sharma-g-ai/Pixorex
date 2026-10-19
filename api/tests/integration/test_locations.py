"""Contracts 2.1-2.9 against PostgreSQL: levels, tree, publish check, publish and the freeze."""

import uuid
from typing import Any

from app.services.locations import PATH_SEPARATOR as SEP
from tests.integration.conftest import Api
from tests.integration.helpers import BO, ERIN, TARA, make_token
from tests.integration.test_s2_identity import P04

LEVELS = [
    {"level_name": "Facility", "requirement": "required"},
    {"level_name": "Building", "requirement": "required"},
    {"level_name": "Shop", "requirement": "optional"},
    {"level_name": "Bin", "requirement": "required"},
]


def _key() -> dict[str, str]:
    return {"Idempotency-Key": str(uuid.uuid4())}


def _problem(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["type"] == f"/problems/{code}"


def _unit(api: Api, facility: str = "Dayton") -> str:
    body = {
        "name": f"Plant {uuid.uuid4().hex[:6]}",
        "facility_name": facility,
        "bu_admin": {"invite_email": f"{uuid.uuid4().hex[:6]}@example.com"},
    }
    return str(api.post("/business-units", ERIN, json=body, headers=_key()).json()["bu_id"])


def _setup(api: Api, unit: str) -> dict[str, Any]:
    return api.get(f"/business-units/{unit}/locations", ERIN).json()


def _level(setup: dict[str, Any], name: str) -> str:
    return next(lv["level_id"] for lv in setup["levels"] if lv["level_name"] == name)


def _named_tree(api: Api, unit: str) -> dict[str, Any]:
    """Levels, the skeleton, every placeholder renamed: Dayton > Hall A > Paint > Bin 1."""
    api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": LEVELS})
    setup = api.post(f"/business-units/{unit}/locations/skeleton", ERIN).json()
    for node, name in zip(setup["nodes"], ["Dayton", "Hall A", "Paint", "Bin 1"], strict=True):
        api.call("PATCH", f"/location-nodes/{node['node_id']}", ERIN, json={"name": name})
    return _setup(api, unit)


def _node(setup: dict[str, Any], name: str) -> dict[str, Any]:
    return next(n for n in setup["nodes"] if n["name"] == name)


def test_levels_rules(api: Api) -> None:
    unit = _unit(api)
    empty = _setup(api, unit)
    assert (empty["status"], empty["levels"], empty["nodes"]) == ("not_published", [], [])
    saved = api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": LEVELS})
    assert saved.status_code == 200, saved.text
    assert [(lv["level_name"], lv["level_order"]) for lv in saved.json()["levels"]] == [
        ("Facility", 1),
        ("Building", 2),
        ("Shop", 3),
        ("Bin", 4),
    ]
    top_optional = [{"level_name": "Site", "requirement": "optional"}]
    _problem(
        api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": top_optional}),
        400,
        "validation",
    )
    twice = [
        {"level_name": "A", "requirement": "required"},
        {"level_name": "a", "requirement": "optional"},
    ]
    _problem(
        api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": twice}),
        400,
        "validation",
    )
    _problem(
        api.put(f"/business-units/{unit}/locations/levels", BO, json={"levels": LEVELS}),
        403,
        "forbidden",
    )


def test_skeleton_names_the_top_after_the_facility(api: Api) -> None:
    unit = _unit(api, facility="Kirlampudi")
    api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": LEVELS})
    setup = api.post(f"/business-units/{unit}/locations/skeleton", ERIN).json()
    assert [n["name"] for n in setup["nodes"]] == ["Kirlampudi", "Building", "Shop", "Bin"]
    assert all(n["is_placeholder"] for n in setup["nodes"])
    assert [n["child_count"] for n in setup["nodes"]] == [1, 1, 1, 0]
    _problem(api.post(f"/business-units/{unit}/locations/skeleton", ERIN), 409, "tree-not-empty")


def test_placeholders_block_publishing_until_renamed(api: Api) -> None:
    unit = _unit(api)
    api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": LEVELS})
    setup = api.post(f"/business-units/{unit}/locations/skeleton", ERIN).json()
    check = api.get(f"/business-units/{unit}/locations/publish-check", ERIN).json()
    assert (check["placeholders_left"], check["can_publish"]) == (4, False)
    _problem(
        api.post(f"/business-units/{unit}/locations/publish", ERIN), 409, "publish-checks-failed"
    )
    renamed = api.call(
        "PATCH", f"/location-nodes/{setup['nodes'][1]['node_id']}", ERIN, json={"name": "Hall A"}
    )
    assert (renamed.json()["name"], renamed.json()["is_placeholder"]) == ("Hall A", False)


def test_adding_nodes_respects_levels_and_sibling_names(api: Api) -> None:
    unit = _unit(api)
    setup = _named_tree(api, unit)
    top, hall = _node(setup, "Dayton"), _node(setup, "Hall A")
    added = api.post(
        f"/business-units/{unit}/locations/nodes",
        ERIN,
        headers=_key(),
        json={
            "parent_id": top["node_id"],
            "level_id": _level(setup, "Building"),
            "names": ["Hall B", "Hall C"],
        },
    )
    assert added.status_code == 201, added.text
    assert [n["name"] for n in added.json()["nodes"]] == ["Hall B", "Hall C"]
    _problem(
        api.post(
            f"/business-units/{unit}/locations/nodes",
            ERIN,
            headers=_key(),
            json={
                "parent_id": top["node_id"],
                "level_id": _level(setup, "Building"),
                "names": ["Hall B"],
            },
        ),
        409,
        "duplicate-name",
    )
    # Shop is optional: a Bin may go straight into a Hall.
    straight = api.post(
        f"/business-units/{unit}/locations/nodes",
        ERIN,
        headers=_key(),
        json={"parent_id": hall["node_id"], "level_id": _level(setup, "Bin"), "names": ["Bin 9"]},
    )
    assert straight.status_code == 201, straight.text
    # Building is required: a Bin may not skip it.
    _problem(
        api.post(
            f"/business-units/{unit}/locations/nodes",
            ERIN,
            headers=_key(),
            json={
                "parent_id": top["node_id"],
                "level_id": _level(setup, "Bin"),
                "names": ["Bin X"],
            },
        ),
        400,
        "wrong-level",
    )
    _problem(
        api.post(
            f"/business-units/{unit}/locations/nodes",
            ERIN,
            headers=_key(),
            json={
                "parent_id": hall["node_id"],
                "level_id": _level(setup, "Facility"),
                "names": ["Up"],
            },
        ),
        400,
        "wrong-level",
    )


def test_moving_only_to_a_parent_at_the_same_level(api: Api) -> None:
    unit = _unit(api)
    setup = _named_tree(api, unit)
    top, paint = _node(setup, "Dayton"), _node(setup, "Paint")
    new_hall = api.post(
        f"/business-units/{unit}/locations/nodes",
        ERIN,
        headers=_key(),
        json={
            "parent_id": top["node_id"],
            "level_id": _level(setup, "Building"),
            "names": ["Hall B"],
        },
    ).json()["nodes"][0]
    moved = api.call(
        "PATCH",
        f"/location-nodes/{paint['node_id']}",
        ERIN,
        json={"parent_id": new_hall["node_id"]},
    )
    assert moved.status_code == 200, moved.text
    assert moved.json()["parent_id"] == new_hall["node_id"]
    after = _setup(api, unit)
    assert _node(after, "Bin 1")["parent_id"] == paint["node_id"]  # its contents came along
    _problem(
        api.call(
            "PATCH", f"/location-nodes/{paint['node_id']}", ERIN, json={"parent_id": top["node_id"]}
        ),
        400,
        "wrong-level",
    )
    _problem(
        api.call(
            "PATCH",
            f"/location-nodes/{paint['node_id']}",
            ERIN,
            json={"name": "X", "parent_id": top["node_id"]},
        ),
        400,
        "validation",
    )


def test_check_publish_freeze_and_published_tree(api: Api, owner_sql: Any) -> None:
    unit = _unit(api)
    setup = _named_tree(api, unit)
    top = _node(setup, "Dayton")
    empty_hall = api.post(
        f"/business-units/{unit}/locations/nodes",
        ERIN,
        headers=_key(),
        json={
            "parent_id": top["node_id"],
            "level_id": _level(setup, "Building"),
            "names": ["Hall Empty"],
        },
    ).json()["nodes"][0]
    check = api.get(f"/business-units/{unit}/locations/publish-check", ERIN).json()
    assert check["placeholders_left"] == 0 and check["can_publish"] is True
    assert [b["node_id"] for b in check["empty_branches"]] == [empty_hall["node_id"]]
    assert check["empty_branches"][0]["path"] == SEP.join(["Dayton", "Hall Empty"])
    assert check["sample_path"] == SEP.join(["Dayton", "Hall A", "Paint", "Bin 1"])
    assert api.call("DELETE", f"/location-nodes/{empty_hall['node_id']}", ERIN).status_code == 204

    _problem(
        api.get(f"/business-units/{unit}/locations/published", ERIN), 404, "locations-not-published"
    )
    published = api.post(f"/business-units/{unit}/locations/publish", ERIN)
    assert published.status_code == 200, published.text
    assert published.json()["status"] == "published"

    node_id = _node(_setup(api, unit), "Paint")["node_id"]
    _problem(
        api.call("PATCH", f"/location-nodes/{node_id}", ERIN, json={"name": "Y"}),
        409,
        "locked-after-publish",
    )
    _problem(api.call("DELETE", f"/location-nodes/{node_id}", ERIN), 409, "locked-after-publish")
    _problem(
        api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": LEVELS}),
        409,
        "locked-after-publish",
    )
    _problem(
        api.post(f"/business-units/{unit}/locations/publish", ERIN), 409, "locked-after-publish"
    )

    tree = api.get(f"/business-units/{unit}/locations/published", ERIN).json()
    path = tree["tree_snapshot"]["nodes"][0]
    assert path["name"] == "Dayton" and path["children"][0]["children"][0]["name"] == "Paint"
    _problem(api.get(f"/business-units/{unit}/locations/published", TARA), 403, "forbidden")
    unit_row = next(
        u for u in api.get("/business-units?limit=100", ERIN).json()["items"] if u["bu_id"] == unit
    )
    assert unit_row["locations_status"] == "published"
    audit = owner_sql(
        "SELECT count(*) FROM audit_log WHERE bu_id = %s AND category = 'locations'", (unit,)
    )
    assert audit[0][0] >= 8


def test_reorder_that_breaks_the_tree_is_refused_and_new_levels_start_optional(api: Api) -> None:
    unit = _unit(api)
    setup = _named_tree(api, unit)
    ids = {lv["level_name"]: lv["level_id"] for lv in setup["levels"]}
    swapped = [
        {"level_id": ids["Facility"], "level_name": "Facility", "requirement": "required"},
        {"level_id": ids["Shop"], "level_name": "Shop", "requirement": "optional"},
        {"level_id": ids["Building"], "level_name": "Building", "requirement": "required"},
        {"level_id": ids["Bin"], "level_name": "Bin", "requirement": "required"},
    ]
    _problem(
        api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": swapped}),
        400,
        "wrong-level",
    )
    with_new = [
        swapped[0],
        {"level_name": "Zone", "requirement": "required"},
        swapped[2],
        swapped[1],
        swapped[3],
    ]
    saved = api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": with_new})
    assert saved.status_code == 200, saved.text
    zone = next(lv for lv in saved.json()["levels"] if lv["level_name"] == "Zone")
    assert (zone["level_order"], zone["requirement"]) == (2, "optional")


def test_who_may_see_locations(api: Api) -> None:
    _problem(api.get(f"/business-units/{P04}/locations", BO), 403, "forbidden")  # EA only
    _problem(api.get(f"/business-units/{uuid.uuid4()}/locations", ERIN), 404, "not-found")
    other_tenant = make_token(
        str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/user/b-ea")),
        tenant_id=str(uuid.uuid5(uuid.NAMESPACE_URL, "pixorex-seed/tenant/b")),
    )
    _problem(api.get(f"/business-units/{P04}/locations", token=other_tenant), 404, "not-found")


def test_level_list_rules_found_in_review(api: Api) -> None:
    unit = _unit(api)
    setup = _named_tree(api, unit)
    ids = {lv["level_name"]: lv["level_id"] for lv in setup["levels"]}
    twice = [
        {"level_id": ids["Facility"], "level_name": "Facility", "requirement": "required"},
        {"level_id": ids["Facility"], "level_name": "Again", "requirement": "optional"},
    ]
    _problem(
        api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": twice}),
        400,
        "validation",
    )
    off = [
        {"level_id": ids[n], "level_name": n, "requirement": "off" if n == "Shop" else r}
        for n, r in (
            ("Facility", "required"),
            ("Building", "required"),
            ("Shop", "optional"),
            ("Bin", "required"),
        )
    ]
    _problem(
        api.put(f"/business-units/{unit}/locations/levels", ERIN, json={"levels": off}),
        400,
        "validation",
    )  # Shop has the "Paint" location
