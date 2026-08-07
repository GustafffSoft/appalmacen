from __future__ import annotations

import asyncio
import logging

from app.models.schemas import (
    ScanProductCatalogRequest,
    ScanProductCatalogResponse,
    ScannedCatalogProduct,
)
from app.services.firebase_service import (
    create_scanned_catalog_product_if_missing,
    get_product_by_sku,
)
from app.services.openai_service import extract_catalog_products_from_images_with_ai

logger = logging.getLogger(__name__)
_MAX_CONCURRENT_IMAGE_ANALYSES = 3


class ProductCatalogScanError(RuntimeError):
    pass


def _clean_product(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    sku = str(raw.get("sku") or "").strip().upper()
    description = str(raw.get("description") or "").strip()
    if not sku or not description:
        return None
    alternate_skus = sorted(
        {
            str(value).strip().upper()
            for value in raw.get("alternateSkus", [])
            if str(value).strip() and str(value).strip().upper() != sku
        }
    )
    return {
        "sku": sku,
        "description": description,
        "secondName": str(raw.get("secondName") or "").strip() or None,
        "category": str(raw.get("category") or "Otro").strip() or "Otro",
        "brand": str(raw.get("brand") or "").strip() or None,
        "manufacturer": str(raw.get("manufacturer") or "").strip() or None,
        "packDescription": str(raw.get("packDescription") or "").strip() or None,
        "unitsPerCase": max(1, int(raw.get("unitsPerCase") or 1)),
        "alternateSkus": alternate_skus,
        "barcode": str(raw.get("barcode") or "").strip() or None,
        "color": str(raw.get("color") or "").strip() or None,
        "material": str(raw.get("material") or "").strip() or None,
        "size": str(raw.get("size") or "").strip() or None,
    }


async def _extract_single_image(
    image_number: int,
    image_url: str,
    semaphore: asyncio.Semaphore,
) -> tuple[int, list[object], str | None]:
    try:
        async with semaphore:
            extracted = await extract_catalog_products_from_images_with_ai([image_url])
        products = extracted.get("products", [])
        if not isinstance(products, list):
            products = []
        return image_number, products, None
    except Exception as error:  # noqa: BLE001
        logger.exception(
            "Catalog image analysis failed image_number=%s error_type=%s",
            image_number,
            type(error).__name__,
        )
        return image_number, [], type(error).__name__


def _add_clean_products(
    raw_products: list[object],
    cleaned_by_sku: dict[str, dict],
) -> int:
    skipped_count = 0
    for raw in raw_products:
        product = _clean_product(raw)
        if product is None:
            skipped_count += 1
            continue
        cleaned_by_sku.setdefault(product["sku"], product)
    return skipped_count


async def scan_product_catalog(
    request: ScanProductCatalogRequest,
) -> ScanProductCatalogResponse:
    image_urls = [
        str(page.imageUrl or "").strip() for page in request.pages if page.imageUrl
    ]
    if not image_urls:
        return ScanProductCatalogResponse(
            products=[],
            createdSkus=[],
            existingSkus=[],
            skippedCount=0,
            message="No se recibieron imagenes validas.",
        )

    semaphore = asyncio.Semaphore(_MAX_CONCURRENT_IMAGE_ANALYSES)
    page_results = await asyncio.gather(
        *(
            _extract_single_image(index, image_url, semaphore)
            for index, image_url in enumerate(image_urls, start=1)
        )
    )

    cleaned_by_sku: dict[str, dict] = {}
    skipped_count = 0
    failed_pages = [number for number, _products, error in page_results if error]
    for _number, raw_products, _error in page_results:
        skipped_count += _add_clean_products(raw_products, cleaned_by_sku)

    retry_used = False
    retry_error: Exception | None = None
    if not cleaned_by_sku:
        retry_used = True
        try:
            retry_payload = await extract_catalog_products_from_images_with_ai(
                image_urls,
                retry_for_empty=True,
            )
            retry_products = retry_payload.get("products", [])
            if isinstance(retry_products, list):
                skipped_count += _add_clean_products(
                    retry_products,
                    cleaned_by_sku,
                )
        except Exception as error:  # noqa: BLE001
            retry_error = error
            logger.exception(
                "Catalog scan recovery failed page_count=%s error_type=%s",
                len(image_urls),
                type(error).__name__,
            )

    if len(failed_pages) == len(image_urls) and retry_error is not None:
        raise ProductCatalogScanError(
            "No se pudieron analizar las imagenes. Intenta nuevamente con fotos claras."
        ) from retry_error

    created_skus: list[str] = []
    existing_skus: list[str] = []
    response_products: list[ScannedCatalogProduct] = []
    for sku, product in cleaned_by_sku.items():
        if get_product_by_sku(sku):
            status = "existing"
            existing_skus.append(sku)
        elif create_scanned_catalog_product_if_missing(product):
            status = "created"
            created_skus.append(sku)
        else:
            status = "existing"
            existing_skus.append(sku)
        response_products.append(ScannedCatalogProduct(**product, status=status))

    if response_products:
        message = (
            f"{len(response_products)} productos detectados: "
            f"{len(created_skus)} creados y {len(existing_skus)} ya existentes."
        )
    else:
        message = (
            "No se detectaron productos. Toma una foto clara, recta y completa; "
            "verifica que se vean las columnas de codigo y descripcion."
        )
    if failed_pages:
        message += (
            f" {len(failed_pages)} de {len(image_urls)} imagen(es) no pudieron "
            "analizarse."
        )

    logger.info(
        "Catalog scan completed pages=%s failed_pages=%s products=%s created=%s "
        "existing=%s skipped=%s recovery_used=%s",
        len(image_urls),
        len(failed_pages),
        len(response_products),
        len(created_skus),
        len(existing_skus),
        skipped_count,
        retry_used,
    )
    return ScanProductCatalogResponse(
        products=response_products,
        createdSkus=created_skus,
        existingSkus=existing_skus,
        skippedCount=skipped_count,
        message=message,
    )
