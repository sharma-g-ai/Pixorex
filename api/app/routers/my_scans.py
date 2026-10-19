"""Contracts 3.1, 3.2: a technician's own scans."""

from datetime import date
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Header, Query

from app.auth.context import SignedIn
from app.core.paging import Cursor, Limit
from app.services import my_scans

router = APIRouter(tags=["My Scans"])


@router.get("/me/scans", operation_id="listMyScans")
async def list_my_scans(
    session: SignedIn,
    bu_id: UUID | None = None,
    tab: Literal["all", "needs_action", "in_progress", "approved"] | None = None,
    review_status: str | None = None,
    equipment_type_id: UUID | None = None,
    from_: Annotated[date | None, Query(alias="from")] = None,
    to: date | None = None,
    q: str | None = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> my_scans.MyScanPage:
    return await my_scans.list_mine(
        session,
        tab=tab,
        bu_id=bu_id,
        review_status=review_status,
        equipment_type_id=equipment_type_id,
        from_=from_,
        to=to,
        q=q,
        cursor=cursor,
        limit=limit,
    )


@router.post("/scans/{scan_id}/revisions", operation_id="submitRevision", status_code=201)
async def submit_revision(
    scan_id: UUID,
    body: my_scans.RevisionInput,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],  # TODO (open point): required, not stored yet
) -> my_scans.Revision:
    return await my_scans.submit(session, scan_id, body)
