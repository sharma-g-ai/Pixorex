"""App factory. Run locally: uv run uvicorn --factory app.main:create_app --reload"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from app.auth.keycloak_admin import KeycloakAdmin
from app.auth.tokens import Jwks
from app.core import storage
from app.core.config import Settings, get_settings
from app.core.correlation import CorrelationMiddleware
from app.core.db import create_pool
from app.core.logging import configure_logging
from app.core.problems import install_problem_handlers
from app.routers import (
    activity,
    business_units,
    equipment_types,
    exports,
    internal,
    invites,
    locations,
    me,
    my_scans,
    operations,
    review,
    scans,
    staff,
)

API_PREFIX = "/api/v1"


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.settings = settings
        app.state.pool = create_pool(settings)
        app.state.storage = storage.config_from(
            minio_url=settings.minio_url,
            minio_public_url=settings.minio_public_url,
            access_key=settings.minio_access_key,
            secret_key=settings.minio_secret_key,
            bucket=settings.minio_bucket,
        )
        # Don't block start-up on the database; /ready reports it until it is reachable.
        await app.state.pool.open(wait=False)
        async with httpx.AsyncClient(timeout=settings.readiness_timeout_s) as http:
            app.state.http = http
            app.state.jwks = Jwks(
                f"{settings.keycloak_realm_url}/protocol/openid-connect/certs", http
            )
            app.state.keycloak = KeycloakAdmin(
                realm_url=settings.keycloak_realm_url,
                client_id=settings.keycloak_admin_client_id,
                client_secret=settings.keycloak_admin_secret,
                http=http,
            )
            yield
        await app.state.pool.close()

    docs = settings.docs_enabled
    app = FastAPI(
        title="Pixorex V1 API",
        lifespan=lifespan,
        docs_url=f"{API_PREFIX}/docs" if docs else None,
        redoc_url=None,
        openapi_url=f"{API_PREFIX}/openapi.json" if docs else None,
    )
    install_problem_handlers(app)
    app.add_middleware(CorrelationMiddleware)
    for router in (
        operations.router,
        me.router,
        invites.router,
        business_units.router,
        staff.router,
        locations.router,
        equipment_types.router,
        activity.router,
        review.router,
        exports.router,
        scans.router,
        my_scans.router,
    ):
        app.include_router(router, prefix=API_PREFIX)
    # Keycloak's listener posts to /internal/keycloak-events (docs/keycloak.md 8.3), outside the
    # public /api/v1 path so deployed ingress can block it.
    app.include_router(internal.router)
    return app
