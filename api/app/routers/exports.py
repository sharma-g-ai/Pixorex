"""Contracts 4.1, 4.2: CSV exports of scans and the audit log."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, Request, Response
from fastapi.responses import JSONResponse

from app.auth.context import SignedIn
from app.services import exports, idempotency

router = APIRouter(tags=["Exports"])


@router.post(
    "/exports",
    operation_id="createExport",
    response_class=Response,
    responses={
        200: {"description": "Up to 1,000 rows: the CSV file", "content": {"text/csv": {}}},
        202: {"description": "Over 1,000 rows: queued", "model": exports.ExportJob},
    },
)
async def create_export(
    body: exports.ExportInput,
    request: Request,
    session: SignedIn,
    idempotency_key: Annotated[UUID, Header()],
) -> Response:
    async def run() -> Response:
        csv_text, job = await exports.create(session, body, request.app.state.storage)
        if job is not None:
            return JSONResponse(job.model_dump(mode="json"), status_code=202)
        name = exports.file_name(body.export_kind)
        return Response(
            content=csv_text,
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": f'attachment; filename="{name}"'},
        )

    return await idempotency.once(session, request, idempotency_key, run)


@router.get("/exports/{export_id}", operation_id="getExport")
async def get_export(export_id: UUID, request: Request, session: SignedIn) -> exports.ExportJob:
    return await exports.get(session, export_id, request.app.state.storage)
