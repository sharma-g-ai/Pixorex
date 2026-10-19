"""Internal endpoints, not in the public contract and hidden from the API docs."""

from fastapi import APIRouter, Request, Response

from app.auth.keycloak_events import valid_signature
from app.core.problems import ProblemError
from app.services import keycloak_events

router = APIRouter(include_in_schema=False)


@router.post("/internal/keycloak-events", status_code=204, response_class=Response)
async def keycloak_event(request: Request) -> Response:
    """docs/keycloak.md 8.3: signed by Keycloak's listener; safe to receive twice."""
    secret = request.app.state.settings.keycloak_events_secret
    if secret is None:
        raise ProblemError(404, "not-found")
    body = await request.body()
    if not valid_signature(secret, body, request.headers.get("x-pixorex-signature")):
        raise ProblemError(401, "unauthorized", "The event signature is not valid.")
    await keycloak_events.handle(request.app.state.pool, request.app.state.keycloak, body)
    return Response(status_code=204)
