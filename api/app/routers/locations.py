"""Contracts 2.1-2.9: a unit's location levels and tree, and publishing them."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, Response
from pydantic import BaseModel

from app.auth.context import SignedIn
from app.services import locations

router = APIRouter(tags=["Locations"])


class Levels(BaseModel):
    levels: list[locations.LevelInput]


@router.get("/business-units/{bu_id}/locations", operation_id="getLocationSetup")
async def get_setup(bu_id: UUID, session: SignedIn) -> locations.LocationSetup:
    return await locations.get_setup(session, bu_id)


@router.put("/business-units/{bu_id}/locations/levels", operation_id="setLocationLevels")
async def set_levels(bu_id: UUID, body: Levels, session: SignedIn) -> locations.LocationSetup:
    return await locations.set_levels(session, bu_id, body.levels)


@router.post("/business-units/{bu_id}/locations/skeleton", operation_id="createLocationSkeleton")
async def create_skeleton(bu_id: UUID, session: SignedIn) -> locations.LocationSetup:
    return await locations.create_skeleton(session, bu_id)


@router.post(
    "/business-units/{bu_id}/locations/nodes", operation_id="addLocationNodes", status_code=201
)
async def add_nodes(
    bu_id: UUID,
    body: locations.NewNodes,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],
) -> locations.AddedNodes:
    # TODO (open point): Idempotency-Key is required but not stored yet (no table in the model).
    return await locations.add_nodes(session, bu_id, body)


@router.patch("/location-nodes/{node_id}", operation_id="updateLocationNode")
async def update_node(
    node_id: UUID, body: locations.NodeChange, session: SignedIn
) -> locations.LocationNode:
    return await locations.change_node(session, node_id, body)


@router.delete("/location-nodes/{node_id}", operation_id="deleteLocationNode", status_code=204)
async def delete_node(node_id: UUID, session: SignedIn) -> Response:
    await locations.delete_node(session, node_id)
    return Response(status_code=204)


@router.get("/business-units/{bu_id}/locations/publish-check", operation_id="checkLocationPublish")
async def publish_check(bu_id: UUID, session: SignedIn) -> locations.PublishCheck:
    return await locations.publish_check(session, bu_id)


@router.post("/business-units/{bu_id}/locations/publish", operation_id="publishLocations")
async def publish(bu_id: UUID, session: SignedIn) -> locations.Published:
    return await locations.publish(session, bu_id)


@router.get("/business-units/{bu_id}/locations/published", operation_id="getPublishedLocations")
async def published(bu_id: UUID, session: SignedIn) -> locations.PublishedTree:
    return await locations.published_tree(session, bu_id)
