from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.db import close_pool, init_pool
from app.routers import bu_admins, business_units, health, invites, me


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_pool()
    yield
    close_pool()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="Pixorex API", version="0.1.0", lifespan=lifespan)
    origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins or ["http://localhost:5173"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(health.router, prefix="/api/v1")
    app.include_router(me.router, prefix="/api/v1")
    app.include_router(invites.router, prefix="/api/v1")
    app.include_router(business_units.router, prefix="/api/v1")
    app.include_router(bu_admins.router, prefix="/api/v1")
    return app


app = create_app()
