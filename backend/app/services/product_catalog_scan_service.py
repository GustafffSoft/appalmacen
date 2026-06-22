from __future__ import annotations

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

    extracted = await extract_catalog_products_from_images_with_ai(image_urls)
    raw_products = extracted.get("products", [])
    cleaned_by_sku: dict[str, dict] = {}
    skipped_count = 0
    for raw in raw_products if isinstance(raw_products, list) else []:
        product = _clean_product(raw)
        if product is None:
            skipped_count += 1
            continue
        cleaned_by_sku.setdefault(product["sku"], product)

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

    message = (
        f"{len(response_products)} productos detectados: "
        f"{len(created_skus)} creados y {len(existing_skus)} ya existentes."
    )
    return ScanProductCatalogResponse(
        products=response_products,
        createdSkus=created_skus,
        existingSkus=existing_skus,
        skippedCount=skipped_count,
        message=message,
    )
