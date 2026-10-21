"""Equipment types (contracts 2.10-2.20, PRD FR-3.1-3.4): draft, fields, publish."""

import re
from datetime import datetime
from typing import Any, Literal
from uuid import UUID

import httpx
from psycopg.errors import UniqueViolation
from pydantic import BaseModel, Field, ValidationError

from app.auth.context import Session
from app.core.paging import PageInfo, decode_cursor, encode_cursor
from app.core.problems import ProblemError
from app.repositories import audit
from app.repositories import equipment_types as repo
from app.services import ai_proxy

DataType = Literal["text", "number", "date", "dropdown", "boolean"]
DEFAULT_FLAG_BELOW = 0.85


class FieldInput(BaseModel):
    label: str = Field(min_length=1, max_length=100)
    data_type: DataType
    options: list[str] | None = None
    is_required: bool
    is_critical: bool
    format_rule: str | None = None
    is_unique_in_unit: bool = False
    flag_below_confidence: float = Field(default=DEFAULT_FLAG_BELOW, ge=0, le=1)


class FieldChange(BaseModel):
    """Contract 2.16: at least one property."""

    label: str | None = Field(default=None, min_length=1, max_length=100)
    data_type: DataType | None = None
    options: list[str] | None = None
    is_required: bool | None = None
    is_critical: bool | None = None
    format_rule: str | None = None
    is_unique_in_unit: bool | None = None
    flag_below_confidence: float | None = Field(default=None, ge=0, le=1)


class TypeField(FieldInput):
    field_id: UUID
    field_key: str
    sort_order: int
    origin: Literal["manual", "ai_suggested"]


class EquipmentType(BaseModel):
    type_id: UUID
    name: str
    status: Literal["not_published", "published"]
    created_via: Literal["blank", "copy", "ai_assist"]
    copied_from_type_id: UUID | None
    version_no: int
    field_count: int
    published_at: datetime | None
    fields: list[TypeField] | None = None


class TypePage(BaseModel):
    items: list[EquipmentType]
    page: PageInfo


class NewType(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    created_via: Literal["blank", "copy", "ai_assist"]
    copied_from_type_id: UUID | None = None
    fields: list[FieldInput] | None = None


class FieldList(BaseModel):
    fields: list[TypeField]


class Published(BaseModel):
    status: Literal["published"]
    published_at: datetime
    contract_id: UUID


class SuggestedField(BaseModel):
    label: str
    data_type: DataType


class Suggestions(BaseModel):
    suggested_fields: list[SuggestedField]


# ---- shared ----------------------------------------------------------------------------


def _type(row: dict[str, Any], fields: list[dict[str, Any]] | None = None) -> EquipmentType:
    return EquipmentType(
        **{k: row[k] for k in EquipmentType.model_fields if k in row},
        fields=[TypeField(**f) for f in fields] if fields is not None else None,
    )


async def _with_fields(session: Session, row: dict[str, Any]) -> EquipmentType:
    grouped = await repo.fields(session.conn, [row["version_id"]])
    return _type(row, grouped[row["version_id"]])


def _admin_only_sees_published(session: Session, bu_id: UUID) -> bool:
    """Technicians see only published types (contracts 2.10, 2.12)."""
    caller = session.caller
    return not caller.is_ea and bu_id not in caller.units("bu_admin")


async def _draft(session: Session, type_id: UUID) -> dict[str, Any]:
    """A type the caller runs (x-roles bu_admin), still not published."""
    row = await repo.one(session.conn, type_id, lock=True)
    if row is None:
        raise ProblemError(404, "not-found")
    session.caller.require_bu_admin_of(row["bu_id"])
    if row["status"] == "published":
        raise ProblemError(409, "locked-after-publish", "A published type can't change.")
    return row


async def _audit(session: Session, bu_id: UUID, action: str, summary: str, type_id: UUID) -> None:
    await audit.record(
        session.conn,
        tenant_id=session.caller.tenant_id,
        actor_user_id=session.caller.user_id,
        bu_id=bu_id,
        category="equipment_types",
        action=action,
        summary=summary,
        object_type="equipment_type",
        object_id=type_id,
    )


def _clean_name(name: str) -> str:
    cleaned = " ".join(name.split())
    if not cleaned:
        raise ProblemError(400, "validation", "Enter a name.")
    return cleaned


def _field_key(label: str, taken: set[str]) -> str:
    """The key in revision values: from the label, unique in the type."""
    base = re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_") or "field"
    key, n = base, 2
    while key in taken:
        key, n = f"{base}_{n}", n + 1
    return key


def _field_values(field: FieldInput) -> dict[str, Any]:
    """Validated column values. A dropdown needs 2+ different choices (contract 2.15);
    other types keep no choices."""
    label = " ".join(field.label.split())
    if not label:
        raise ProblemError(400, "validation", "Enter a label.")
    options = None
    if field.data_type == "dropdown":
        options = [" ".join(o.split()) for o in field.options or []]
        if len([o for o in options if o]) < 2 or len(set(options)) != len(options) or "" in options:
            raise ProblemError(400, "validation", "A dropdown needs 2 or more different choices.")
    format_rule = (field.format_rule or "").strip() or None
    return {
        "label": label,
        "data_type": field.data_type,
        "options": options,
        "is_required": field.is_required,
        "is_critical": field.is_critical,
        "format_rule": format_rule,
        "is_unique_in_unit": field.is_unique_in_unit,
        "flag_below_confidence": field.flag_below_confidence,
    }


async def _insert_field(session: Session, version_id: UUID, field: FieldInput, origin: str) -> UUID:
    values = _field_values(field)
    taken, last = await repo.keys_and_order(session.conn, version_id)
    try:
        return await repo.add_field(
            session.conn,
            tenant_id=session.caller.tenant_id,
            version_id=version_id,
            values={
                **values,
                "field_key": _field_key(values["label"], taken),
                "sort_order": last + 1,
                "origin": origin,
            },
        )
    except UniqueViolation:
        raise ProblemError(
            409, "duplicate-name", "That label is already used in this type."
        ) from None


# ---- 2.10 - 2.14 ---------------------------------------------------------------------------


async def list_types(
    session: Session,
    bu_id: UUID,
    *,
    status: str | None,
    include_fields: bool,
    cursor: str | None,
    limit: int,
) -> TypePage:
    caller = session.caller
    if not caller.is_ea and bu_id not in caller.bu_ids:
        raise ProblemError(403, "forbidden")
    if _admin_only_sees_published(session, bu_id):
        if status == "not_published":
            return TypePage(items=[], page=PageInfo(next_cursor=None))
        status = "published"
    rows = await repo.page(
        session.conn, bu_id=bu_id, status=status, after=decode_cursor(cursor, 2), limit=limit
    )
    more = len(rows) > limit
    rows = rows[:limit]
    grouped = (
        await repo.fields(session.conn, [r["version_id"] for r in rows]) if include_fields else {}
    )
    return TypePage(
        items=[_type(r, grouped.get(r["version_id"]) if include_fields else None) for r in rows],
        page=PageInfo(
            next_cursor=encode_cursor(rows[-1]["name"], rows[-1]["type_id"]) if more else None
        ),
    )


async def create_type(session: Session, bu_id: UUID, body: NewType) -> EquipmentType:
    """Contract 2.11: blank, a copy (with the source's fields), or AI-assisted (the ticked
    suggestions, origin ai_suggested). Always not published, version 1."""
    session.caller.require_bu_admin_of(bu_id)
    name = _clean_name(body.name)
    if (body.created_via == "copy") != (body.copied_from_type_id is not None):
        raise ProblemError(400, "validation", "A copy needs the type it copies, and only a copy.")
    if body.fields and body.created_via != "ai_assist":
        raise ProblemError(400, "validation", "Fields can be sent only with AI assist.")
    source = None
    if body.copied_from_type_id:
        source = await repo.one(session.conn, body.copied_from_type_id)
        if source is None or source["bu_id"] != bu_id:
            raise ProblemError(400, "validation", "Copy a type of this unit.")
    process_id = await repo.default_process(session.conn, bu_id)
    if process_id is None:
        raise ProblemError(404, "not-found")
    try:
        type_id = await repo.create(
            session.conn,
            tenant_id=session.caller.tenant_id,
            bu_id=bu_id,
            process_id=process_id,
            name=name,
            created_via=body.created_via,
            copied_from=body.copied_from_type_id,
        )
    except UniqueViolation:
        raise ProblemError(409, "duplicate-name", "A type with this name already exists.") from None
    created = await repo.one(session.conn, type_id)
    if created is None:
        raise RuntimeError("the new type is not visible to its creator")
    if source is not None:
        for field in (await repo.fields(session.conn, [source["version_id"]]))[
            source["version_id"]
        ]:
            await _insert_field(
                session, created["version_id"], FieldInput(**field), field["origin"]
            )
    for suggestion in body.fields or []:
        await _insert_field(session, created["version_id"], suggestion, "ai_suggested")
    await _audit(
        session, bu_id, "equipment_type.created", f"Created equipment type {name}", type_id
    )
    row = await repo.one(session.conn, type_id)
    if row is None:
        raise RuntimeError("the new type disappeared")
    return await _with_fields(session, row)


async def get_type(session: Session, type_id: UUID) -> EquipmentType:
    row = await repo.one(session.conn, type_id)
    caller = session.caller
    if row is None or (not caller.is_ea and row["bu_id"] not in caller.bu_ids):
        raise ProblemError(404, "not-found")
    if row["status"] != "published" and _admin_only_sees_published(session, row["bu_id"]):
        raise ProblemError(404, "not-found")
    return await _with_fields(session, row)


async def rename_type(session: Session, type_id: UUID, name: str) -> EquipmentType:
    row = await _draft(session, type_id)
    new_name = _clean_name(name)
    try:
        await repo.rename(session.conn, type_id, new_name)
    except UniqueViolation:
        raise ProblemError(409, "duplicate-name", "A type with this name already exists.") from None
    await _audit(
        session,
        row["bu_id"],
        "equipment_type.renamed",
        f"Renamed {row['name']} to {new_name}",
        type_id,
    )
    return await get_type(session, type_id)


async def delete_type(session: Session, type_id: UUID) -> None:
    row = await _draft(session, type_id)
    await repo.delete(session.conn, type_id)
    await _audit(
        session,
        row["bu_id"],
        "equipment_type.deleted",
        f"Deleted equipment type {row['name']}",
        type_id,
    )


# ---- 2.15 - 2.19 ---------------------------------------------------------------------------


async def add_field(session: Session, type_id: UUID, field: FieldInput) -> TypeField:
    row = await _draft(session, type_id)
    field_id = await _insert_field(session, row["version_id"], field, "manual")
    await _audit(
        session,
        row["bu_id"],
        "equipment_type.field_added",
        f"Added field {field.label.strip()} to {row['name']}",
        type_id,
    )
    return await _field(session, field_id, row["version_id"])


async def _field(session: Session, field_id: UUID, version_id: UUID) -> TypeField:
    found = await repo.field(session.conn, field_id, version_id)
    if found is None:
        raise ProblemError(404, "not-found")
    return TypeField(**found)


async def change_field(
    session: Session, type_id: UUID, field_id: UUID, change: FieldChange
) -> TypeField:
    changes = change.model_dump(exclude_unset=True)
    if not changes:
        raise ProblemError(400, "validation", "Change at least one setting.")
    row = await _draft(session, type_id)
    current = await _field(session, field_id, row["version_id"])
    try:
        merged = FieldInput(**{**current.model_dump(), **changes})
    except ValidationError as exc:  # e.g. null for a setting that can't be empty
        fields = ", ".join(str(e["loc"][0]) for e in exc.errors())
        raise ProblemError(400, "validation", f"Not a valid value: {fields}.") from None
    if merged.data_type != "dropdown":
        merged.options = None
    values = _field_values(merged)
    taken, _ = await repo.keys_and_order(session.conn, row["version_id"])
    key = (
        current.field_key
        if values["label"] == current.label
        else _field_key(values["label"], taken - {current.field_key})
    )
    try:
        await repo.update_field(session.conn, field_id, {**values, "field_key": key})
    except UniqueViolation:
        raise ProblemError(
            409, "duplicate-name", "That label is already used in this type."
        ) from None
    await _audit(
        session,
        row["bu_id"],
        "equipment_type.field_changed",
        f"Changed field {values['label']} in {row['name']}",
        type_id,
    )
    return await _field(session, field_id, row["version_id"])


async def remove_field(session: Session, type_id: UUID, field_id: UUID) -> None:
    row = await _draft(session, type_id)
    current = await _field(session, field_id, row["version_id"])
    await repo.delete_field(session.conn, field_id)
    await _audit(
        session,
        row["bu_id"],
        "equipment_type.field_removed",
        f"Removed field {current.label} from {row['name']}",
        type_id,
    )


async def reorder_fields(session: Session, type_id: UUID, field_ids: list[UUID]) -> FieldList:
    """Contract 2.18: every field exactly once."""
    row = await _draft(session, type_id)
    current = (await repo.fields(session.conn, [row["version_id"]]))[row["version_id"]]
    if sorted(map(str, field_ids)) != sorted(str(f["field_id"]) for f in current):
        raise ProblemError(400, "validation", "Send every field of the type exactly once.")
    await repo.set_order(session.conn, row["version_id"], field_ids)
    fields = (await repo.fields(session.conn, [row["version_id"]]))[row["version_id"]]
    return FieldList(fields=[TypeField(**f) for f in fields])


async def publish(session: Session, type_id: UUID) -> Published:
    """Contract 2.19: freezes version 1 and its fields; binds the current prompt version."""
    row = await _draft(session, type_id)
    if row["field_count"] == 0:
        raise ProblemError(409, "no-fields", "Add at least one field before publishing.")
    prompt_id = await repo.current_prompt_version(session.conn)
    if prompt_id is None:
        # Prompt versions are platform-owned (FR-3.5); Amzur adds them.
        raise ProblemError(
            409, "no-prompt-version", "Publishing is not available yet: no AI prompt is set up."
        )
    done = await repo.publish(
        session.conn,
        tenant_id=session.caller.tenant_id,
        type_id=type_id,
        version_id=row["version_id"],
        prompt_id=prompt_id,
        user_id=session.caller.user_id,
    )
    await _audit(
        session,
        row["bu_id"],
        "equipment_type.published",
        f"Published equipment type {row['name']}",
        type_id,
    )
    return Published(status="published", **done)


MAX_SUGGEST_PHOTO = 10 * 1024 * 1024  # a label photo from a phone or a screenshot
PHOTO_TYPES = {b"\xff\xd8\xff": "image/jpeg", b"\x89PNG\r\n\x1a\n": "image/png"}


def photo_type(image: bytes) -> str | None:
    """JPEG or PNG, by the file's first bytes (not by what the browser says)."""
    return next((mime for start, mime in PHOTO_TYPES.items() if image.startswith(start)), None)


async def suggest_fields(
    session: Session,
    bu_id: UUID,
    *,
    name: str,
    image: bytes,
    http: httpx.AsyncClient,
    ai: ai_proxy.AiConfig | None,
) -> Suggestions:
    """Contract 2.20: the AI proxy reads the label photo; nothing is saved. The admin ticks
    the fields they want and creates the type (2.11, created_via ai_assist)."""
    session.caller.require_bu_admin_of(bu_id)
    if not name.strip():
        raise ProblemError(400, "validation", "Give the new type a name.")
    mime = photo_type(image)
    if mime is None:
        raise ProblemError(400, "validation", "The photo must be a JPEG or PNG.")
    if ai is None:
        raise ProblemError(
            503, "ai-unavailable", "AI assist isn't available yet. Start blank or copy a type."
        )
    try:
        fields = await ai_proxy.suggest_fields(
            http, ai, type_name=name.strip(), image=image, mime=mime
        )
    except ai_proxy.AiUnavailableError:
        raise ProblemError(
            503,
            "ai-unavailable",
            "AI assist couldn't read the photo right now. Try again, or start blank.",
        ) from None
    return Suggestions(suggested_fields=[SuggestedField(**f) for f in fields])
