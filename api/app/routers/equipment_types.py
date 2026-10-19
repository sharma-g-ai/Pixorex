"""Contracts 2.10-2.20: equipment types of a unit, their fields, publishing."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Header, Response
from pydantic import BaseModel, Field

from app.auth.context import SignedIn
from app.core.paging import Cursor, Limit
from app.services import equipment_types as types

router = APIRouter(tags=["Equipment types"])


class TypeName(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class FieldOrder(BaseModel):
    field_ids: list[UUID]


@router.get("/business-units/{bu_id}/equipment-types", operation_id="listEquipmentTypes")
async def list_types(
    bu_id: UUID,
    session: SignedIn,
    status: Literal["not_published", "published"] | None = None,
    include: Literal["fields"] | None = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> types.TypePage:
    return await types.list_types(
        session,
        bu_id,
        status=status,
        include_fields=include == "fields",
        cursor=cursor,
        limit=limit,
    )


@router.post(
    "/business-units/{bu_id}/equipment-types",
    operation_id="createEquipmentType",
    status_code=201,
)
async def create_type(
    bu_id: UUID,
    body: types.NewType,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],
) -> types.EquipmentType:
    # TODO (open point): Idempotency-Key is required but not stored yet (no table in the model).
    return await types.create_type(session, bu_id, body)


@router.get("/equipment-types/{type_id}", operation_id="getEquipmentType")
async def get_type(type_id: UUID, session: SignedIn) -> types.EquipmentType:
    return await types.get_type(session, type_id)


@router.patch("/equipment-types/{type_id}", operation_id="renameEquipmentType")
async def rename_type(type_id: UUID, body: TypeName, session: SignedIn) -> types.EquipmentType:
    return await types.rename_type(session, type_id, body.name)


@router.delete("/equipment-types/{type_id}", operation_id="deleteEquipmentType", status_code=204)
async def delete_type(type_id: UUID, session: SignedIn) -> Response:
    await types.delete_type(session, type_id)
    return Response(status_code=204)


@router.post("/equipment-types/{type_id}/fields", operation_id="addField", status_code=201)
async def add_field(
    type_id: UUID,
    body: types.FieldInput,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],
) -> types.TypeField:
    return await types.add_field(session, type_id, body)


@router.patch("/equipment-types/{type_id}/fields/{field_id}", operation_id="updateField")
async def update_field(
    type_id: UUID, field_id: UUID, body: types.FieldChange, session: SignedIn
) -> types.TypeField:
    return await types.change_field(session, type_id, field_id, body)


@router.delete(
    "/equipment-types/{type_id}/fields/{field_id}", operation_id="removeField", status_code=204
)
async def remove_field(type_id: UUID, field_id: UUID, session: SignedIn) -> Response:
    await types.remove_field(session, type_id, field_id)
    return Response(status_code=204)


@router.put("/equipment-types/{type_id}/field-order", operation_id="reorderFields")
async def reorder_fields(type_id: UUID, body: FieldOrder, session: SignedIn) -> types.FieldList:
    return await types.reorder_fields(session, type_id, body.field_ids)


@router.post("/equipment-types/{type_id}/publish", operation_id="publishEquipmentType")
async def publish(type_id: UUID, session: SignedIn) -> types.Published:
    return await types.publish(session, type_id)


@router.post("/business-units/{bu_id}/equipment-types/ai-suggest", operation_id="suggestFields")
async def suggest_fields(bu_id: UUID, session: SignedIn) -> types.Suggestions:
    # The body (name + image, multipart) is not read: the AI proxy is not built yet.
    return await types.suggest_fields(session, bu_id)
