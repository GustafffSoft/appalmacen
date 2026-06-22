from functools import lru_cache
from pathlib import Path
import os

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parents[2]
load_dotenv(BASE_DIR / '.env')


class Settings:
    def __init__(self) -> None:
        self.firebase_project_id = os.getenv('FIREBASE_PROJECT_ID', '')
        self.firebase_storage_bucket = os.getenv('FIREBASE_STORAGE_BUCKET', '')
        self.google_application_credentials = os.getenv(
            'GOOGLE_APPLICATION_CREDENTIALS', './serviceAccountKey.json'
        )
        self.allow_overhang_cm_default = float(os.getenv('ALLOW_OVERHANG_CM_DEFAULT', '2'))
        self.pallet_length_cm_default = float(os.getenv('PALLET_LENGTH_CM_DEFAULT', '120'))
        self.pallet_width_cm_default = float(os.getenv('PALLET_WIDTH_CM_DEFAULT', '100'))
        self.pallet_max_height_cm_default = float(os.getenv('PALLET_MAX_HEIGHT_CM_DEFAULT', '180'))
        self.pallet_max_weight_kg_default = float(os.getenv('PALLET_MAX_WEIGHT_KG_DEFAULT', '900'))
        self.max_download_size_mb = int(os.getenv('MAX_DOWNLOAD_SIZE_MB', '15'))
        self.tesseract_cmd = os.getenv('TESSERACT_CMD', '')
        self.openai_api_key = os.getenv('OPENAI_API_KEY', '')
        self.openai_model = os.getenv('OPENAI_MODEL', 'gpt-5.2')
        self.upload_dir = BASE_DIR / 'uploads'
        self.log_dir = BASE_DIR / 'logs'
        self.allowed_image_extensions = {'.jpg', '.jpeg', '.png'}


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    settings.log_dir.mkdir(parents=True, exist_ok=True)
    return settings
