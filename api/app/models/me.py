from uuid import UUID

from pydantic import BaseModel, EmailStr


class UnitRole(BaseModel):
    bu_id: UUID | None
    name: str | None = None
    role: str
    is_primary: bool
    assigned_by_name: str | None = None


class Me(BaseModel):
    user_id: UUID
    full_name: str
    email: EmailStr
    phone_number: str | None = None
    status: str
    tenant_name: str
    units: list[UnitRole]
    active_bu_id: UUID | None
    last_bu_id: UUID | None


class ActiveUnitBody(BaseModel):
    bu_id: UUID
