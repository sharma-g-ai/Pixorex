from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class InvitePreviewBody(BaseModel):
    token: str = Field(min_length=8)


class InviteAcceptBody(BaseModel):
    token: str = Field(min_length=8)
    full_name: str = Field(min_length=1, max_length=200)
    phone_number: str | None = None


class CreateInviteBody(BaseModel):
    role: str
    email: EmailStr
    bu_ids: list[UUID] = Field(min_length=1)


class UnitRef(BaseModel):
    bu_id: UUID
    name: str


class InvitePreview(BaseModel):
    role: str
    email: EmailStr
    units: list[UnitRef]
    invited_by_name: str
    expires_at: datetime


class InviteAcceptResult(BaseModel):
    user_id: UUID
    next_step: str


class InviteRow(BaseModel):
    invite_id: UUID
    email: EmailStr
    role: str
    units: list[UnitRef]
    invited_by_name: str
    created_at: datetime
    expires_at: datetime
    status: str
