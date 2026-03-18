from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter, ImageOps

from app.core.config import get_settings


class OcrUnavailableError(RuntimeError):
    pass


def _score_text(text: str) -> int:
    upper = text.upper()
    score = 0
    for keyword in ['INVOICE', 'SKU', 'QTY', 'TOTAL', 'SUBTOTAL', 'DATE', 'BILL TO']:
        score += upper.count(keyword) * 5
    score += sum(char.isdigit() for char in text)
    score += text.count('\n')
    return score


def _prepare_variants(image: Image.Image) -> list[Image.Image]:
    base = ImageOps.exif_transpose(image).convert('L')
    enlarged = base.resize((base.width * 2, base.height * 2))
    high_contrast = ImageEnhance.Contrast(enlarged).enhance(2.5)
    sharpened = high_contrast.filter(ImageFilter.SHARPEN)
    thresholded = sharpened.point(lambda value: 255 if value > 165 else 0)
    soft_threshold = sharpened.point(lambda value: 255 if value > 140 else 0)
    return [enlarged, sharpened, thresholded, soft_threshold]


def extract_text_from_image(image_path: Path) -> str:
    try:
        import pytesseract
    except ImportError as exc:
        raise OcrUnavailableError('pytesseract no esta instalado en el backend.') from exc

    settings = get_settings()
    if settings.tesseract_cmd:
        pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
    elif shutil.which('tesseract') is None:
        raise OcrUnavailableError(
            'Tesseract OCR no esta instalado. Instala Tesseract o define TESSERACT_CMD en backend/.env.'
        )

    image = Image.open(image_path)
    variants = _prepare_variants(image)
    configs = [
        '--oem 3 --psm 6',
        '--oem 3 --psm 11',
        '--oem 3 --psm 4',
    ]

    best_text = ''
    best_score = -1
    for variant in variants:
        for config in configs:
            text = pytesseract.image_to_string(variant, config=config).strip()
            score = _score_text(text)
            if score > best_score:
                best_score = score
                best_text = text

    return best_text
