"""Locations setup (contracts 2.1-2.9, PRD FR-2.1-2.3): levels, the node tree, publish."""

import json
from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from psycopg.errors import UniqueViolation
from pydantic import BaseModel, Field

from app.auth.context import Session
from app.core.problems import ProblemError
from app.repositories import audit
from app.repositories import locations as repo

Requirement = Literal["required", "optional", "off"]
PATH_SEPARATOR = f" {chr(0x203A)} "  # right-pointing angle quote, as the web shows paths


class Level(BaseModel):
    level_id: UUID
    level_name: str
    level_order: int
    requirement: Requirement


class LevelInput(BaseModel):
    level_id: UUID | None = None
    level_name: str = Field(min_length=1, max_length=100)
    requirement: Requirement


class LocationNode(BaseModel):
    node_id: UUID
    parent_id: UUID | None
    level_id: UUID
    name: str
    is_placeholder: bool
    child_count: int


class LocationSetup(BaseModel):
    version_id: UUID
    status: Literal["not_published", "published"]
    levels: list[Level]
    nodes: list[LocationNode]


class NewNodes(BaseModel):
    parent_id: UUID
    level_id: UUID
    names: list[str] = Field(min_length=1, max_length=50)


class AddedNodes(BaseModel):
    nodes: list[LocationNode]


class NodeChange(BaseModel):
    """Exactly one of the two (contract 2.5: minProperties 1, maxProperties 1)."""

    name: str | None = Field(default=None, min_length=1, max_length=200)
    parent_id: UUID | None = None


class PublishCheck(BaseModel):
    counts: dict[str, int]  # node count per level, keyed by level_id
    placeholders_left: int
    empty_branches: list[dict[str, Any]]  # [{node_id, path}]
    sample_path: str | None
    can_publish: bool


class Published(BaseModel):
    status: Literal["published"]
    published_at: datetime


class PublishedTree(BaseModel):
    levels: list[Level]
    tree_snapshot: dict[str, Any]
    published_at: datetime


# ---- shared ----------------------------------------------------------------------------


async def _version(session: Session, bu_id: UUID, *, lock: bool = False) -> dict[str, Any]:
    found = await repo.version(session.conn, bu_id, lock=lock)
    if found is None:  # not a unit of this tenant, or not visible to the caller
        raise ProblemError(404, "not-found")
    return found


def _unpublished(version: dict[str, Any]) -> None:
    if version["status"] == "published":
        raise ProblemError(409, "locked-after-publish", "Locations can't change after publishing.")


async def _setup(session: Session, version: dict[str, Any]) -> LocationSetup:
    return LocationSetup(
        version_id=version["id"],
        status=version["status"],
        levels=[Level(**lv) for lv in await repo.levels(session.conn, version["id"])],
        nodes=[LocationNode(**n) for n in await repo.nodes(session.conn, version["id"])],
    )


async def _audit(
    session: Session, bu_id: UUID, action: str, summary: str, node: UUID | None = None
) -> None:
    await audit.record(
        session.conn,
        tenant_id=session.caller.tenant_id,
        actor_user_id=session.caller.user_id,
        bu_id=bu_id,
        category="locations",
        action=action,
        summary=summary,
        object_type="location_node" if node else "location_hierarchy_version",
        object_id=node,
    )


def _clean(name: str) -> str:
    cleaned = " ".join(name.split())
    if not cleaned or len(cleaned) > 200:
        raise ProblemError(400, "validation", "Each name needs 1 to 200 characters.")
    return cleaned


# ---- 2.1 - 2.3 -----------------------------------------------------------------------------


async def get_setup(session: Session, bu_id: UUID) -> LocationSetup:
    session.caller.require_ea()
    return await _setup(session, await _version(session, bu_id))


async def set_levels(session: Session, bu_id: UUID, wanted: list[LevelInput]) -> LocationSetup:
    """Contract 2.2: replaces the whole list; order = position; top level always required."""
    session.caller.require_ea()
    version = await _version(session, bu_id, lock=True)
    _unpublished(version)
    if not wanted:
        raise ProblemError(400, "validation", "Add at least one level.")
    names = [" ".join(w.level_name.split()) for w in wanted]
    if "" in names or len({n.lower() for n in names}) != len(names):
        raise ProblemError(400, "validation", "Level names must be filled in and different.")
    if wanted[0].requirement != "required":
        raise ProblemError(400, "validation", "The top level is always required.")

    sent_ids = [w.level_id for w in wanted if w.level_id]
    if len(set(sent_ids)) != len(sent_ids):
        raise ProblemError(400, "validation", "A level appears twice.")
    current = {lv["level_id"]: lv for lv in await repo.levels(session.conn, version["id"])}
    if any(w.level_id and w.level_id not in current for w in wanted):
        raise ProblemError(400, "validation", "A level does not belong to this unit.")
    in_use = await repo.levels_in_use(session.conn, version["id"])
    if any(w.level_id in in_use and w.requirement == "off" for w in wanted):
        raise ProblemError(400, "validation", "A level that has locations can't be turned off.")
    dropped = set(current) - {w.level_id for w in wanted if w.level_id}
    if dropped & in_use:
        raise ProblemError(400, "validation", "A level that has locations can't be removed.")

    # A new level above existing locations starts optional (contract 2.2): their parents
    # skip it. Above the top level there is no way to skip, so that is refused.
    deepest_new_above = [
        i
        for i, w in enumerate(wanted)
        if w.level_id is None and any(x.level_id in in_use for x in wanted[i + 1 :])
    ]
    if 0 in deepest_new_above:
        raise ProblemError(400, "validation", "A new top level can't go above existing locations.")
    rows = [
        {
            "level_id": w.level_id,
            "level_name": names[i],
            "requirement": "optional" if i in deepest_new_above else w.requirement,
        }
        for i, w in enumerate(wanted)
    ]
    await repo.save_levels(
        session.conn, tenant_id=session.caller.tenant_id, version_id=version["id"], wanted=rows
    )
    if await repo.misplaced_nodes(session.conn, version["id"]):
        raise ProblemError(400, "wrong-level", "That order would put locations above their parent.")
    await _audit(session, bu_id, "locations.levels_saved", f"Saved {len(rows)} location levels")
    return await _setup(session, version)


async def create_skeleton(session: Session, bu_id: UUID) -> LocationSetup:
    """Contract 2.3: one placeholder per level in use, the top one named after the facility."""
    session.caller.require_ea()
    version = await _version(session, bu_id, lock=True)
    _unpublished(version)
    if await repo.nodes(session.conn, version["id"]):
        raise ProblemError(409, "tree-not-empty", "The tree already has locations.")
    levels = [
        lv for lv in await repo.levels(session.conn, version["id"]) if lv["requirement"] != "off"
    ]
    if not levels:
        raise ProblemError(400, "validation", "Set the levels first.")
    parent: dict[str, Any] | None = None
    for i, level in enumerate(levels):
        parent = await repo.add_node(
            session.conn,
            tenant_id=session.caller.tenant_id,
            version_id=version["id"],
            level_id=level["level_id"],
            parent=parent,
            name=version["facility_name"] if i == 0 else level["level_name"],
            placeholder=True,
        )
    await _audit(session, bu_id, "locations.skeleton_created", "Created the location placeholders")
    return await _setup(session, version)


# ---- 2.4 - 2.6 -----------------------------------------------------------------------------


async def add_nodes(session: Session, bu_id: UUID, body: NewNodes) -> AddedNodes:
    """Contract 2.4: the level must sit below the parent's level; optional (or off) levels
    in between may be skipped, required ones may not."""
    session.caller.require_ea()
    version = await _version(session, bu_id, lock=True)
    _unpublished(version)
    names = [_clean(n) for n in body.names]
    if len(set(names)) != len(names):  # same rule as the database: exact names
        raise ProblemError(409, "duplicate-name", "The same name appears twice.")
    parent = await repo.node(session.conn, body.parent_id)
    if parent is None or parent["version_id"] != version["id"]:
        raise ProblemError(404, "not-found")
    levels = await repo.levels(session.conn, version["id"])
    order = {lv["level_id"]: lv["level_order"] for lv in levels}
    target = next((lv for lv in levels if lv["level_id"] == body.level_id), None)
    if target is None or target["requirement"] == "off":
        raise ProblemError(400, "wrong-level", "Pick a level that is in use.")
    skipped = [
        lv for lv in levels if order[parent["level_id"]] < lv["level_order"] < target["level_order"]
    ]
    if target["level_order"] <= order[parent["level_id"]] or any(
        lv["requirement"] == "required" for lv in skipped
    ):
        raise ProblemError(
            400, "wrong-level", "That level doesn't go directly inside this location."
        )
    added = []
    try:
        for name in names:
            added.append(
                await repo.add_node(
                    session.conn,
                    tenant_id=session.caller.tenant_id,
                    version_id=version["id"],
                    level_id=body.level_id,
                    parent=parent,
                    name=name,
                )
            )
    except UniqueViolation:
        raise ProblemError(
            409, "duplicate-name", "A location with that name is already there."
        ) from None
    summary = (
        f"Added {len(added)} {'location' if len(added) == 1 else 'locations'} in {parent['name']}"
    )
    await _audit(session, bu_id, "locations.nodes_added", summary, parent["node_id"])
    return AddedNodes(nodes=[LocationNode(**n) for n in added])


async def _editable_node(session: Session, node_id: UUID) -> dict[str, Any]:
    session.caller.require_ea()
    found = await repo.node(session.conn, node_id)
    if found is None:
        raise ProblemError(404, "not-found")
    _unpublished(await _version(session, found["bu_id"], lock=True))
    return found


async def change_node(session: Session, node_id: UUID, change: NodeChange) -> LocationNode:
    """Contract 2.5: rename (clears the placeholder flag) or move to a parent at the same
    level as the old parent."""
    if (change.name is None) == (change.parent_id is None):
        raise ProblemError(400, "validation", "Send either a new name or a new parent.")
    node = await _editable_node(session, node_id)
    try:
        if change.name is not None:
            name = _clean(change.name)
            await repo.rename(session.conn, node_id, name)
            await _audit(
                session,
                node["bu_id"],
                "locations.node_renamed",
                f"Renamed {node['name']} to {name}",
                node_id,
            )
        else:
            old_parent = (
                await repo.node(session.conn, node["parent_id"]) if node["parent_id"] else None
            )
            new_parent = (
                await repo.node(session.conn, change.parent_id) if change.parent_id else None
            )
            if new_parent is None or new_parent["version_id"] != node["version_id"]:
                raise ProblemError(404, "not-found")
            if old_parent is None or new_parent["level_id"] != old_parent["level_id"]:
                raise ProblemError(400, "wrong-level", "Move it into a location at the same level.")
            await repo.move(session.conn, node, new_parent)
            await _audit(
                session,
                node["bu_id"],
                "locations.node_moved",
                f"Moved {node['name']} to {new_parent['name']}",
                node_id,
            )
    except UniqueViolation:
        raise ProblemError(
            409, "duplicate-name", "A location with that name is already there."
        ) from None
    updated = await repo.node(session.conn, node_id)
    if updated is None:
        raise RuntimeError("the node disappeared")
    return LocationNode(**updated)


async def delete_node(session: Session, node_id: UUID) -> None:
    """Contract 2.6: the node and everything inside it."""
    node = await _editable_node(session, node_id)
    await repo.delete(session.conn, node_id)
    await _audit(
        session,
        node["bu_id"],
        "locations.node_deleted",
        f"Deleted {node['name']} and its contents",
        node_id,
    )


# ---- 2.7 - 2.9 -----------------------------------------------------------------------------


def _names_by_id(nodes: list[dict[str, Any]]) -> dict[str, str]:
    return {str(n["node_id"]): n["name"] for n in nodes}


def _readable(path: str, names: dict[str, str]) -> str:
    return PATH_SEPARATOR.join(names[i] for i in path.strip("/").split("/") if i in names)


async def _check(session: Session, version: dict[str, Any]) -> PublishCheck:
    levels = await repo.levels(session.conn, version["id"])
    nodes = await repo.nodes(session.conn, version["id"])
    names = _names_by_id(nodes)
    order = {lv["level_id"]: lv["level_order"] for lv in levels}
    deepest_required = max(
        (lv["level_order"] for lv in levels if lv["requirement"] == "required"), default=0
    )
    # A branch is empty when it stops above a required level: a technician can't finish picking.
    empty = [
        {"node_id": str(n["node_id"]), "path": _readable(n["path"], names)}
        for n in nodes
        if n["child_count"] == 0 and order[n["level_id"]] < deepest_required
    ]
    complete = [
        n for n in nodes if n["child_count"] == 0 and order[n["level_id"]] >= deepest_required
    ]
    placeholders = sum(1 for n in nodes if n["is_placeholder"])
    return PublishCheck(
        counts={
            str(lv["level_id"]): sum(1 for n in nodes if n["level_id"] == lv["level_id"])
            for lv in levels
        },
        placeholders_left=placeholders,
        empty_branches=empty,
        sample_path=_readable(complete[0]["path"], names) if complete else None,
        # Contract 2.8: publishing is refused while placeholders are left (and needs a tree).
        can_publish=version["status"] != "published" and bool(nodes) and placeholders == 0,
    )


async def publish_check(session: Session, bu_id: UUID) -> PublishCheck:
    session.caller.require_ea()
    return await _check(session, await _version(session, bu_id))


def _snapshot(nodes: list[dict[str, Any]]) -> dict[str, Any]:
    """Frozen tree cached by the phone: nested nodes, top level first (contract 2.9)."""
    children: dict[str | None, list[dict[str, Any]]] = {}
    for n in nodes:
        children.setdefault(str(n["parent_id"]) if n["parent_id"] else None, []).append(n)

    def build(parent: str | None) -> list[dict[str, Any]]:
        return [
            {
                "node_id": str(n["node_id"]),
                "level_id": str(n["level_id"]),
                "name": n["name"],
                "children": build(str(n["node_id"])),
            }
            for n in sorted(children.get(parent, []), key=lambda x: x["name"].lower())
        ]

    return {"nodes": build(None)}


async def publish(session: Session, bu_id: UUID) -> Published:
    """Contract 2.8: freezes levels and nodes for good (version 1)."""
    session.caller.require_ea()
    version = await _version(session, bu_id, lock=True)
    _unpublished(version)
    check = await _check(session, version)
    if not check.can_publish:
        raise ProblemError(409, "publish-checks-failed", "Name the placeholders first.")
    nodes = await repo.nodes(session.conn, version["id"])
    done = await repo.publish(
        session.conn, version["id"], json.dumps(_snapshot(nodes)), session.caller.user_id
    )
    await _audit(session, bu_id, "locations.published", "Published the locations")
    return Published(status="published", published_at=done["published_at"])


async def published_tree(session: Session, bu_id: UUID) -> PublishedTree:
    """Contract 2.9: for anyone with a role in the unit, and the EA."""
    caller = session.caller
    if not caller.is_ea and bu_id not in caller.bu_ids:
        raise ProblemError(403, "forbidden")
    version = await _version(session, bu_id)
    if version["status"] != "published":
        raise ProblemError(
            404, "locations-not-published", "This unit's locations aren't published yet."
        )
    return PublishedTree(
        levels=[Level(**lv) for lv in await repo.levels(session.conn, version["id"])],
        tree_snapshot=version["tree_snapshot"],
        published_at=version["published_at"],
    )
