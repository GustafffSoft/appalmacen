from __future__ import annotations

from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

import requests

from app.core.config import get_settings
from app.utils.download import download_url_to_file


def _extract_extension(image_url: str, content_type: str | None) -> str:
    parsed = urlparse(image_url)
    suffix = Path(parsed.path).suffix.lower()
    if suffix in {".jpg", ".jpeg", ".png"}:
        return suffix

    if content_type:
        lowered = content_type.lower()
        if "jpeg" in lowered or "jpg" in lowered:
            return ".jpg"
        if "png" in lowered:
            return ".png"

    raise ValueError("Unsupported image type. Only JPG and PNG are allowed.")


def download_image(image_url: str) -> Path:
    settings = get_settings()
    content_type: str | None = None

    try:
        head_response = requests.head(image_url, allow_redirects=True, timeout=15)
        if head_response.status_code < 400:
            content_type = head_response.headers.get("content-type")
        elif head_response.status_code not in {403, 405}:
            raise ValueError(f"Could not access image URL ({head_response.status_code})")
    except requests.RequestException:
        pass

    ext = _extract_extension(image_url, content_type)
    if ext not in settings.allowed_image_extensions:
        raise ValueError("Unsupported image extension")

    local_name = f"order_{uuid4().hex}{ext}"
    destination = settings.upload_dir / local_name
    max_bytes = settings.max_download_size_mb * 1024 * 1024

    return download_url_to_file(image_url, destination, max_bytes)