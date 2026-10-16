from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, model_validator


class CreateBusinessUnitBody(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    facility_name: str = Field(min_length=1, max_length=200)
    bu_admin: dict

    @model_validator(mode="after")
    def require_one_admin_shape(self) -> CreateBusinessUnitBody:
        admin = self.bu_admin
        has_email = "invite_email" in admin and admin["invite_email"]
        has_user = "user_id" in admin and admin["user_id"]
        if has_email == has_user:
            raise ValueError("bu_admin must be either {invite_email} or {user_id}")
        return self

    @property
    def invite_email(self) -> str | None:
        raw = self.bu_admin.get("invite_email")
        return str(raw).strip().lower() if raw else None

    @property
    def existing_user_id(self) -> UUID | None:
        raw = self.bu_admin.get("user_id")
        return UUID(str(raw)) if raw else None


class UserRef(BaseModel):
    user_id: UUID
    full_name: str


class BusinessUnit(BaseModel):
    bu_id: UUID
    name: str
    facility_name: str
    bu_admin: UserRef | None
    waiting_count: int = 0
    escalated_count: int = 0
    delegated_count: int = 0
    locations_status: str


class PageInfo(BaseModel):
    next_cursor: str | None = None


class BusinessUnitList(BaseModel):
    items: list[BusinessUnit]
    page: PageInfo


class BuAdminUnitRef(BaseModel):
    bu_id: UUID
    name: str


class BuAdmin(BaseModel):
    user_id: UUID
    full_name: str
    email: EmailStr
    units: list[BuAdminUnitRef]
    status: str
    last_active_at: datetime | None = None


class BuAdminList(BaseModel):
    items: list[BuAdmin]
    page: PageInfo
