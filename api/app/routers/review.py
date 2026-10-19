"""Contracts 3.3-3.18: review queue, decisions, delegation, escalations, all scans."""

from datetime import date
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Header, Query, Request, Response

from app.auth.context import SignedIn
from app.core.paging import Cursor, Limit
from app.core.problems import ProblemError
from app.services import delegation, oversight, review

router = APIRouter(tags=["Review"])
IdempotencyKey = Annotated[UUID, Header()]  # TODO (open point): required, not stored yet


@router.get("/business-units/{bu_id}/review-queue", operation_id="getReviewQueue")
async def review_queue(
    bu_id: UUID,
    session: SignedIn,
    filter: review.QueueFilter = "waiting",
    cursor: Cursor = None,
    limit: Limit = 25,
) -> review.ReviewQueue:
    return await review.queue(session, bu_id, filter_=filter, cursor=cursor, limit=limit)


@router.get("/scans/{scan_id}/review", operation_id="getScanReview")
async def scan_review(scan_id: UUID, request: Request, session: SignedIn) -> review.ScanReview:
    return await review.scan_review(session, scan_id, request.app.state.storage)


@router.post("/scans/{scan_id}/decisions", operation_id="decideScan", status_code=201)
async def decide(
    scan_id: UUID, body: review.DecisionInput, session: SignedIn, idempotency_key: IdempotencyKey
) -> review.Decided:
    return await review.decide(session, scan_id, body)


@router.get("/business-units/{bu_id}/technician-decisions", operation_id="listTechnicianDecisions")
async def technician_decisions(
    bu_id: UUID,
    session: SignedIn,
    decision: Literal["approved", "rejected"] | None = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> review.TechnicianDecisionPage:
    return await review.technician_decisions(
        session, bu_id, decision=decision, cursor=cursor, limit=limit
    )


@router.post("/decisions/{decision_id}/override", operation_id="overrideDecision", status_code=201)
async def override(
    decision_id: UUID,
    body: review.DecisionInput,
    session: SignedIn,
    idempotency_key: IdempotencyKey,
) -> review.Overridden:
    return await review.override(session, decision_id, body)


def _scan_ids(raw: list[str] | None) -> list[UUID]:
    """Contract 3.8 says comma-separated (explode false); the web's client sends the
    parameter repeated (explode true). Both are read."""
    try:
        return [UUID(x) for part in raw or [] for x in part.split(",") if x.strip()]
    except ValueError:
        raise ProblemError(
            400, "validation", "scan_ids must be scan ids separated by commas."
        ) from None


@router.get("/business-units/{bu_id}/delegates", operation_id="listDelegates")
async def delegates(
    bu_id: UUID,
    session: SignedIn,
    scan_ids: Annotated[list[str] | None, Query()] = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> delegation.DelegatePage:
    return await delegation.delegates(
        session, bu_id, scan_ids=_scan_ids(scan_ids), cursor=cursor, limit=limit
    )


@router.post(
    "/business-units/{bu_id}/review-batches", operation_id="createReviewBatch", status_code=201
)
async def create_batch(
    bu_id: UUID, body: delegation.NewBatch, session: SignedIn, idempotency_key: IdempotencyKey
) -> delegation.Created:
    return await delegation.create_batch(session, bu_id, body)


@router.get("/business-units/{bu_id}/review-batches", operation_id="listReviewBatches")
async def list_batches(
    bu_id: UUID,
    session: SignedIn,
    status: Literal["active", "completed", "taken_back"] | None = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> delegation.BatchPage:
    return await delegation.list_batches(session, bu_id, status=status, cursor=cursor, limit=limit)


@router.get("/me/review-batches", operation_id="listMyReviewBatches")
async def my_batches(
    session: SignedIn, cursor: Cursor = None, limit: Limit = 25
) -> delegation.BatchPage:
    return await delegation.my_batches(session, cursor=cursor, limit=limit)


@router.get("/review-batches/{batch_id}", operation_id="getReviewBatch")
async def get_batch(batch_id: UUID, session: SignedIn) -> delegation.BatchDetail:
    return await delegation.get_batch(session, batch_id)


@router.post("/review-batches/{batch_id}/reassign", operation_id="reassignReviewBatch")
async def reassign(
    batch_id: UUID, body: delegation.Reassign, session: SignedIn
) -> delegation.Reassigned:
    return await delegation.reassign(session, batch_id, body.assigned_to)


@router.post(
    "/review-batches/{batch_id}/take-back", operation_id="takeBackReviewBatch", status_code=204
)
async def take_back(
    batch_id: UUID, session: SignedIn, body: delegation.TakeBack | None = None
) -> Response:
    await delegation.take_back(session, batch_id, body.message if body else None)
    return Response(status_code=204)


@router.post("/review-batches/{batch_id}/remind", operation_id="remindReviewBatch")
async def remind(batch_id: UUID, session: SignedIn) -> delegation.Reminded:
    return await delegation.remind(session, batch_id)


@router.get("/escalations", operation_id="listEscalations")
async def escalations(
    session: SignedIn,
    bu_id: UUID | None = None,
    reason: oversight.Reason | None = None,
    open: bool | None = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> oversight.EscalationPage:
    return await oversight.escalations(
        session, bu_id=bu_id, reason=reason, open_=open, cursor=cursor, limit=limit
    )


@router.post("/business-units/{bu_id}/escalations/remind", operation_id="remindBuAdmin")
async def remind_bu_admin(bu_id: UUID, session: SignedIn) -> oversight.RemindResult:
    return await oversight.remind_bu_admin(session, bu_id)


@router.get("/scans", operation_id="listAllScans")
async def all_scans(
    session: SignedIn,
    bu_id: UUID | None = None,
    review_status: str | None = None,
    delegated: bool | None = None,
    q: str | None = None,
    since: Annotated[date | None, Query(alias="from")] = None,
    until: Annotated[date | None, Query(alias="to")] = None,
    cursor: Cursor = None,
    limit: Limit = 25,
) -> oversight.ScanPage:
    return await oversight.all_scans(
        session,
        bu_id=bu_id,
        review_status=review_status,
        delegated=delegated,
        q=q,
        since=since,
        until=until,
        cursor=cursor,
        limit=limit,
    )
