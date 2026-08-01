from app.api import api_router
from app.core.config import get_settings
from app.core.logging import configure_logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

configure_logging()
settings = get_settings()

app = FastAPI(
    title="appalmacen-backend",
    version="0.1.0",
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins,
    allow_origin_regex=(
        None
        if settings.is_production
        else r"^https?://(localhost|127\.0\.0\.1|10\.\d+\.\d+\.\d+)(:\d+)?$"
    ),
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

app.include_router(api_router, prefix="/api/v1")


@app.get("/")
def root() -> dict[str, str]:
    return {
        "message": "appalmacen backend running",
        "project": settings.firebase_project_id,
    }
