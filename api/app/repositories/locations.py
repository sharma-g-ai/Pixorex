"""Location levels and nodes (contracts 2.1-2.9). One location_hierarchy_version per unit.
The baseline trigger refuses every change once the version is published (PX001)."""

from typing import Any
from uuid import UUID

from app.core.db import Conn


async def version(conn: Conn, bu_id: UUID, *, lock: bool = False) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT v.id, v.tenant_id, v.bu_id, v.status, v.tree_snapshot, v.published_at,"
        " bu.facility_name"
        " FROM location_hierarchy_version v JOIN business_unit bu ON bu.id = v.bu_id"
        " WHERE v.bu_id = %s" + (" FOR UPDATE OF v" if lock else ""),
        (bu_id,),
    )
    return await cur.fetchone()


async def levels(conn: Conn, version_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT id AS level_id, level_name, level_order, requirement FROM location_level_rule"
        " WHERE version_id = %s ORDER BY level_order",
        (version_id,),
    )
    return await cur.fetchall()


async def nodes(conn: Conn, version_id: UUID) -> list[dict[str, Any]]:
    cur = await conn.execute(
        "SELECT n.id AS node_id, n.parent_id, n.level_rule_id AS level_id, n.name,"
        " n.is_placeholder, n.path,"
        " (SELECT count(*) FROM location_node c WHERE c.parent_id = n.id) AS child_count"
        " FROM location_node n WHERE n.version_id = %s ORDER BY n.path",
        (version_id,),
    )
    return await cur.fetchall()


async def node(conn: Conn, node_id: UUID) -> dict[str, Any] | None:
    cur = await conn.execute(
        "SELECT n.id AS node_id, n.version_id, n.parent_id, n.level_rule_id AS level_id, n.name,"
        " n.is_placeholder, n.path, v.bu_id, v.tenant_id,"
        " (SELECT count(*) FROM location_node c WHERE c.parent_id = n.id) AS child_count"
        " FROM location_node n JOIN location_hierarchy_version v ON v.id = n.version_id"
        " WHERE n.id = %s",
        (node_id,),
    )
    return await cur.fetchone()


async def levels_in_use(conn: Conn, version_id: UUID) -> set[UUID]:
    cur = await conn.execute(
        "SELECT DISTINCT level_rule_id FROM location_node WHERE version_id = %s", (version_id,)
    )
    return {r["level_rule_id"] for r in await cur.fetchall()}


async def save_levels(
    conn: Conn, *, tenant_id: UUID, version_id: UUID, wanted: list[dict[str, Any]]
) -> None:
    """wanted: [{level_id or None, level_name, requirement}] top to bottom. Levels left out
    are deleted. Orders move out of the way first so the (version, order) key never clashes."""
    keep = [w["level_id"] for w in wanted if w["level_id"]]
    await conn.execute(
        "DELETE FROM location_level_rule WHERE version_id = %s AND NOT (id = ANY(%s))",
        (version_id, keep),
    )
    await conn.execute(
        "UPDATE location_level_rule SET level_order = level_order + 1000 WHERE version_id = %s",
        (version_id,),
    )
    for order, level in enumerate(wanted, start=1):
        if level["level_id"]:
            await conn.execute(
                "UPDATE location_level_rule SET level_name = %s, requirement = %s,"
                " level_order = %s WHERE id = %s AND version_id = %s",
                (level["level_name"], level["requirement"], order, level["level_id"], version_id),
            )
        else:
            await conn.execute(
                "INSERT INTO location_level_rule (tenant_id, version_id, level_name, level_order,"
                " requirement) VALUES (%s, %s, %s, %s, %s)",
                (tenant_id, version_id, level["level_name"], order, level["requirement"]),
            )


async def misplaced_nodes(conn: Conn, version_id: UUID) -> int:
    """Nodes whose level is not below their parent's level (after a level reorder)."""
    cur = await conn.execute(
        "SELECT count(*) AS n FROM location_node c"
        " JOIN location_node p ON p.id = c.parent_id"
        " JOIN location_level_rule cl ON cl.id = c.level_rule_id"
        " JOIN location_level_rule pl ON pl.id = p.level_rule_id"
        " WHERE c.version_id = %s AND cl.level_order <= pl.level_order",
        (version_id,),
    )
    row = await cur.fetchone()
    return int(row["n"]) if row else 0


async def add_node(
    conn: Conn,
    *,
    tenant_id: UUID,
    version_id: UUID,
    level_id: UUID,
    parent: dict[str, Any] | None,
    name: str,
    placeholder: bool = False,
) -> dict[str, Any]:
    """path is the materialised id path: /top-id/child-id/..."""
    cur = await conn.execute(
        "WITH n AS (SELECT uuidv7() AS id)"
        " INSERT INTO location_node (id, tenant_id, version_id, level_rule_id, parent_id, name,"
        " path, is_placeholder)"
        " SELECT n.id, %s, %s, %s, %s, %s, %s || '/' || n.id, %s FROM n"
        " RETURNING id AS node_id, parent_id, level_rule_id AS level_id, name, is_placeholder,"
        " path, 0 AS child_count",
        (
            tenant_id,
            version_id,
            level_id,
            parent["node_id"] if parent else None,
            name,
            parent["path"] if parent else "",
            placeholder,
        ),
    )
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("INSERT ... RETURNING returned no row")
    return row


async def rename(conn: Conn, node_id: UUID, name: str) -> None:
    await conn.execute(
        "UPDATE location_node SET name = %s, is_placeholder = false WHERE id = %s", (name, node_id)
    )


async def move(conn: Conn, node: dict[str, Any], parent: dict[str, Any]) -> None:
    """New parent; the node's and its descendants' paths follow."""
    new_path = f"{parent['path']}/{node['node_id']}"
    await conn.execute(
        "UPDATE location_node SET parent_id = %s WHERE id = %s",
        (parent["node_id"], node["node_id"]),
    )
    await conn.execute(
        "UPDATE location_node SET path = %s || substr(path, length(%s) + 1)"
        " WHERE version_id = %s AND (path = %s OR path LIKE %s)",
        (new_path, node["path"], node["version_id"], node["path"], node["path"] + "/%"),
    )


async def delete(conn: Conn, node_id: UUID) -> None:
    """Children go with it (ON DELETE CASCADE, contract 2.6)."""
    await conn.execute("DELETE FROM location_node WHERE id = %s", (node_id,))


async def publish(conn: Conn, version_id: UUID, snapshot: str, user_id: UUID) -> dict[str, Any]:
    cur = await conn.execute(
        "UPDATE location_hierarchy_version SET status = 'published', tree_snapshot = %s::jsonb,"
        " published_by = %s, published_at = now() WHERE id = %s RETURNING published_at",
        (snapshot, user_id, version_id),
    )
    row = await cur.fetchone()
    if row is None:
        raise RuntimeError("publish updated no row")
    return row
