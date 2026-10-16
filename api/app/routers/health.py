from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.auth.jwt import keycloak_reachable
from app.db import connection

router = APIRouter(tags=["Health"])


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
def ready() -> JSONResponse:
    checks = {"database": "fail", "keycloak": "fail", "minio": "ok", "vault": "ok"}
    try:
        with connection() as conn:
            conn.execute("SELECT 1")
        checks["database"] = "ok"
    except Exception:
        pass
    if keycloak_reachable():
        checks["keycloak"] = "ok"
    status = "ready" if checks["database"] == "ok" and checks["keycloak"] == "ok" else "not_ready"
    code = 200 if status == "ready" else 503
    return JSONResponse({"status": status, "checks": checks}, status_code=code)
