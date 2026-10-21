"""Contracts 2.21-2.27: capture from the phone and its extraction."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, Path, Request, Response
from fastapi.responses import JSONResponse

from app.auth.context import SignedIn
from app.core.problems import ProblemError
from app.services import idempotency, scans

router = APIRouter(tags=["Capture"])


def _scan_json(scan: scans.Scan) -> dict[str, object]:
    """latest_attempt is an optional object in the contract: left out, not null, before the
    first attempt. Every other null stays (ai_value, confidence... are required, nullable)."""
    data = scan.model_dump(mode="json")
    if data["latest_attempt"] is None:
        del data["latest_attempt"]
    return data


@router.post(
    "/business-units/{bu_id}/scans",
    operation_id="createScan",
    status_code=201,
    response_model=scans.Scan,
    responses={200: {"description": "Same capture again: the first scan", "model": scans.Scan}},
)
async def create_scan(
    bu_id: UUID,
    body: scans.ScanCreate,
    request: Request,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],
) -> JSONResponse:
    scan, created = await scans.create(
        session, bu_id, body, idempotency_key, request.app.state.storage
    )
    return JSONResponse(_scan_json(scan), status_code=201 if created else 200)


async def _limited_body(request: Request) -> bytes:
    """Reads at most one byte over the limit, so an oversized photo is refused without
    holding all of it in memory."""
    data = bytearray()
    async for chunk in request.stream():
        data += chunk
        if len(data) > scans.MAX_PHOTO_BYTES:
            raise ProblemError(400, "photo-too-large", "A photo can be at most 2 MB.")
    return bytes(data)


@router.put(
    "/scans/{scan_id}/photos/{photo_no}",
    operation_id="uploadPhoto",
    status_code=204,
    response_class=Response,
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {"image/jpeg": {"schema": {"type": "string", "format": "binary"}}},
        }
    },
)
async def upload_photo(
    scan_id: UUID,
    photo_no: Annotated[int, Path(ge=1, le=4)],
    request: Request,
    session: SignedIn,
    content_digest: Annotated[str, Header()],
) -> Response:
    if request.headers.get("content-type", "").split(";")[0].strip().lower() != "image/jpeg":
        raise ProblemError(400, "validation", "Send the photo as image/jpeg.")
    body = await _limited_body(request)
    await scans.upload_photo(
        session, scan_id, photo_no, body, content_digest, request.app.state.storage
    )
    return Response(status_code=204)


@router.post("/scans/{scan_id}/upload-complete", operation_id="confirmUpload", status_code=202)
async def confirm_upload(scan_id: UUID, session: SignedIn) -> scans.UploadConfirmed:
    return await scans.confirm_upload(session, scan_id)


@router.get("/scans/{scan_id}", operation_id="getScan", response_model=scans.Scan)
async def get_scan(scan_id: UUID, request: Request, session: SignedIn) -> JSONResponse:
    scan = await scans.get(session, scan_id, request.app.state.storage)
    return JSONResponse(_scan_json(scan))


@router.post(
    "/scans/{scan_id}/retry-extraction",
    operation_id="retryExtraction",
    status_code=202,
    response_model=scans.AttemptSummary,
)
async def retry_extraction(
    scan_id: UUID,
    request: Request,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],
) -> Response:
    async def run() -> Response:
        return idempotency.json_response(await scans.retry(session, scan_id), 202)

    return await idempotency.once(session, request, idempotency_key, run)


@router.post(
    "/scans/{scan_id}/re-extract",
    operation_id="reExtract",
    status_code=202,
    response_model=scans.AttemptSummary,
)
async def re_extract(
    scan_id: UUID,
    body: scans.ReExtract,
    request: Request,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],
) -> Response:
    async def run() -> Response:
        return idempotency.json_response(await scans.re_extract(session, scan_id, body), 202)

    return await idempotency.once(session, request, idempotency_key, run)


@router.post(
    "/scans/{scan_id}/discard", operation_id="discardScan", status_code=204, response_class=Response
)
async def discard_scan(scan_id: UUID, session: SignedIn) -> Response:
    await scans.discard(session, scan_id)
    return Response(status_code=204)
