from functools import lru_cache
from pathlib import Path
import os

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parents[2]
APP_ENV = os.getenv("APP_ENV", "development").strip().lower()
ENV_FILE = BASE_DIR / (
    ".env.production" if APP_ENV in {"prod", "production"} else ".env"
)
load_dotenv(ENV_FILE)


class Settings:
    def __init__(self) -> None:
        self.app_env = APP_ENV
        self.is_production = APP_ENV in {"prod", "production"}
        self.firebase_project_id = os.getenv("FIREBASE_PROJECT_ID", "")
        self.firebase_storage_bucket = os.getenv("FIREBASE_STORAGE_BUCKET", "")
        self.firebase_service_account_json = os.getenv(
            "FIREBASE_SERVICE_ACCOUNT_JSON", ""
        )
        self.google_application_credentials = os.getenv(
            "GOOGLE_APPLICATION_CREDENTIALS", ""
        )
        self.firebase_check_revoked_tokens = self._get_bool(
            "FIREBASE_CHECK_REVOKED_TOKENS", self.is_production
        )
        default_origins = (
            "https://appalmacen-prod-5e987.web.app,"
            "https://appalmacen-prod-5e987.firebaseapp.com"
            if self.is_production
            else "http://localhost:5180,http://127.0.0.1:5180"
        )
        self.cors_allowed_origins = [
            origin.strip()
            for origin in os.getenv("CORS_ALLOWED_ORIGINS", default_origins).split(",")
            if origin.strip()
        ]
        self.allow_overhang_cm_default = float(
            os.getenv("ALLOW_OVERHANG_CM_DEFAULT", "2")
        )
        self.pallet_length_cm_default = float(
            os.getenv("PALLET_LENGTH_CM_DEFAULT", "120")
        )
        self.pallet_width_cm_default = float(
            os.getenv("PALLET_WIDTH_CM_DEFAULT", "100")
        )
        self.pallet_max_height_cm_default = float(
            os.getenv("PALLET_MAX_HEIGHT_CM_DEFAULT", "180")
        )
        self.pallet_max_weight_kg_default = float(
            os.getenv("PALLET_MAX_WEIGHT_KG_DEFAULT", "900")
        )
        self.max_download_size_mb = int(os.getenv("MAX_DOWNLOAD_SIZE_MB", "15"))
        self.tesseract_cmd = os.getenv("TESSERACT_CMD", "")
        self.openai_api_key = os.getenv("OPENAI_API_KEY", "")
        self.openai_model = os.getenv("OPENAI_MODEL", "gpt-5.2")
        self.upload_dir = BASE_DIR / "uploads"
        self.log_dir = BASE_DIR / "logs"
        self.allowed_image_extensions = {".jpg", ".jpeg", ".png"}

    @staticmethod
    def _get_bool(name: str, default: bool) -> bool:
        value = os.getenv(name)
        if value is None:
            return default
        return value.strip().lower() in {"1", "true", "yes", "on"}


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    settings.log_dir.mkdir(parents=True, exist_ok=True)
    return settings
