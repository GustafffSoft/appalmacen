from app.api import api_router
from app.core.config import get_settings
from app.core.logging import configure_logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

configure_logging()
settings = get_settings()

app = FastAPI(title="appalmacen-backend", version="0.1.0")

# Dev CORS for Flutter web local testing.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api/v1")


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "appalmacen backend running", "project": settings.firebase_project_id}