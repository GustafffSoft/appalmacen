from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.core.config import get_settings

_firestore_client: firestore.Client | None = None
DEFAULT_UNKNOWN_PRODUCT = {
    "lengthCm": 16.0,
    "widthCm": 12.0,
    "heightCm": 12.0,
    "weightKg": 10.0,
    "category": "",
    "cost": 0.0,
    "salePrice": 0.0,
    "stockQty": 0,
    "unitsPerCase": 1,
    "productStatus": "activo",
}


def _resolve_credentials_path(raw_path: str) -> Path:
    candidate = Path(raw_path)
    if candidate.is_absolute():
        return candidate
    return (Path(__file__).resolve().parents[2] / candidate).resolve()


def _init_firebase() -> None:
    settings = get_settings()
    if firebase_admin._apps:
        return

    if settings.firebase_service_account_json:
        try:
            credential_payload = json.loads(settings.firebase_service_account_json)
        except json.JSONDecodeError as error:
            raise RuntimeError(
                "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON"
            ) from error
        cred = credentials.Certificate(credential_payload)
    else:
        credentials_path = _resolve_credentials_path(
            settings.google_application_credentials
        )
        if not credentials_path.exists():
            raise RuntimeError(
                f"Firebase credentials file not found at {credentials_path}. "
                "Set GOOGLE_APPLICATION_CREDENTIALS or "
                "FIREBASE_SERVICE_ACCOUNT_JSON."
            )
        cred = credentials.Certificate(str(credentials_path))
    firebase_admin.initialize_app(
        cred,
        {
            "projectId": settings.firebase_project_id,
            "storageBucket": settings.firebase_storage_bucket,
        },
    )


def get_firestore_client() -> firestore.Client:
    global _firestore_client
    if _firestore_client is None:
        _init_firebase()
        _firestore_client = firestore.client()
    return _firestore_client


def update_order_status(
    order_id: str, status: str, extra: dict[str, Any] | None = None
) -> None:
    db = get_firestore_client()
    payload: dict[str, Any] = {
        "status": status,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    if extra:
        payload.update(extra)
    db.collection("orders").document(order_id).set(payload, merge=True)


def save_pallet_plan(order_id: str, payload: dict[str, Any]) -> None:
    db = get_firestore_client()
    write_payload = dict(payload)
    write_payload["orderId"] = order_id
    write_payload["createdAt"] = firestore.SERVER_TIMESTAMP
    db.collection("pallet_plans").document(order_id).set(write_payload, merge=True)


def save_invoice_record(invoice_number: str, payload: dict[str, Any]) -> None:
    db = get_firestore_client()
    write_payload = dict(payload)
    write_payload["invoiceNumber"] = invoice_number
    write_payload["updatedAt"] = firestore.SERVER_TIMESTAMP
    if "createdAt" not in write_payload:
        write_payload["createdAt"] = firestore.SERVER_TIMESTAMP
    db.collection("invoices").document(invoice_number).set(write_payload, merge=True)


def get_invoice(invoice_number: str) -> dict[str, Any]:
    db = get_firestore_client()
    snap = db.collection("invoices").document(invoice_number).get()
    return snap.to_dict() if snap.exists else {}


def get_order(order_id: str) -> dict[str, Any]:
    db = get_firestore_client()
    snap = db.collection("orders").document(order_id).get()
    return snap.to_dict() if snap.exists else {}


def get_order_by_invoice_number(
    invoice_number: str,
) -> tuple[str | None, dict[str, Any] | None]:
    db = get_firestore_client()
    query = (
        db.collection("orders")
        .where(filter=FieldFilter("invoiceNumber", "==", invoice_number))
        .limit(1)
        .stream()
    )
    for doc in query:
        return doc.id, doc.to_dict()
    return None, None


def upsert_order_from_invoice(
    invoice_number: str, payload: dict[str, Any]
) -> tuple[str, bool]:
    db = get_firestore_client()
    order_id, _existing = get_order_by_invoice_number(invoice_number)
    created = False
    if order_id is None:
        doc_ref = db.collection("orders").document()
        order_id = doc_ref.id
        created = True
    else:
        doc_ref = db.collection("orders").document(order_id)

    doc_ref.set(payload, merge=True)
    return order_id, created


def list_products() -> list[dict[str, Any]]:
    db = get_firestore_client()
    docs = db.collection("products").stream()
    result: list[dict[str, Any]] = []
    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        result.append(data)
    return result


def get_product_by_sku(sku: str) -> dict[str, Any] | None:
    db = get_firestore_client()
    clean_sku = str(sku).strip().upper()
    doc = db.collection("products").document(clean_sku).get()
    if doc.exists:
        return doc.to_dict()

    query = (
        db.collection("products")
        .where(filter=FieldFilter("sku", "==", clean_sku))
        .limit(1)
        .stream()
    )
    for row in query:
        return row.to_dict()

    alternate_query = (
        db.collection("products")
        .where(filter=FieldFilter("alternateSkus", "array_contains", clean_sku))
        .limit(1)
        .stream()
    )
    for row in alternate_query:
        return row.to_dict()
    return None


def update_product_research(sku: str, research: dict[str, Any]) -> None:
    db = get_firestore_client()
    clean_sku = str(sku).strip().upper()
    existing = get_product_by_sku(clean_sku) or {}
    has_case_dimensions = bool(research.get("hasCaseDimensions"))
    has_case_weight = bool(research.get("hasCaseWeight"))
    has_product_image = bool(research.get("hasProductImage"))
    has_case_image = bool(research.get("hasCaseImage"))
    product_image_url = str(research.get("productImageUrl") or "").strip()
    case_image_url = str(research.get("caseImageUrl") or "").strip()
    previous_product_images = {
        str(url).strip()
        for url in existing.get("productImageUrls", [])
        if str(url).strip()
    }
    previous_case_images = {
        str(url).strip()
        for url in existing.get("caseImageUrls", [])
        if str(url).strip()
    }
    existing_product_image = str(existing.get("productImageUrl") or "").strip()
    existing_case_image = str(existing.get("caseImageUrl") or "").strip()
    if existing_product_image:
        previous_product_images.add(existing_product_image)
    if existing_case_image:
        previous_case_images.add(existing_case_image)
    previous_reviewed = {
        str(url).strip()
        for url in existing.get("researchReviewedSourceUrls", [])
        if str(url).strip()
    }
    previous_rejected = {
        str(url).strip()
        for url in existing.get("researchRejectedSourceUrls", [])
        if str(url).strip()
    }
    current_sources = {
        str(source.get("url") or "").strip()
        for source in research.get("sources", [])
        if isinstance(source, dict) and str(source.get("url") or "").strip()
    }
    current_reviewed = {
        str(url).strip()
        for url in research.get("reviewedSourceUrls", [])
        if str(url).strip()
    }
    current_rejected = {
        str(url).strip()
        for url in research.get("rejectedSourceUrls", [])
        if str(url).strip()
    }
    payload = {
        "sku": clean_sku,
        "unitsPerCase": max(1, int(research.get("unitsPerCase") or 1)),
        "useCase": str(research.get("useCase") or ""),
        "researchConfidence": str(research.get("confidence") or "low"),
        "researchNeedsManualReview": bool(research.get("needsManualReview", True)),
        "researchNotes": str(research.get("notes") or ""),
        "researchSources": research.get("sources") or [],
        "researchReviewedSourceUrls": sorted(
            previous_reviewed | current_reviewed | current_sources
        ),
        "researchRejectedSourceUrls": sorted(previous_rejected | current_rejected),
        "researchHasCaseDimensions": has_case_dimensions,
        "researchHasCaseWeight": has_case_weight,
        "researchHasProductImage": has_product_image,
        "researchHasCaseImage": has_case_image,
        "researchModel": research.get("model"),
        "researchedAt": firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    if has_product_image and product_image_url:
        previous_product_images.add(product_image_url)
        payload["productImageUrl"] = product_image_url
    if has_case_image and case_image_url:
        previous_case_images.add(case_image_url)
        payload["caseImageUrl"] = case_image_url
    payload["productImageUrls"] = sorted(previous_product_images)
    payload["caseImageUrls"] = sorted(previous_case_images)
    if has_case_dimensions:
        payload["lengthCm"] = round(float(research.get("lengthCm") or 0), 2)
        payload["widthCm"] = round(float(research.get("widthCm") or 0), 2)
        payload["heightCm"] = round(float(research.get("heightCm") or 0), 2)
    else:
        payload["researchSuggestedLengthCm"] = round(
            float(research.get("lengthCm") or 0), 2
        )
        payload["researchSuggestedWidthCm"] = round(
            float(research.get("widthCm") or 0), 2
        )
        payload["researchSuggestedHeightCm"] = round(
            float(research.get("heightCm") or 0), 2
        )
        payload["lengthCm"] = round(
            float(existing.get("lengthCm") or DEFAULT_UNKNOWN_PRODUCT["lengthCm"]), 2
        )
        payload["widthCm"] = round(
            float(existing.get("widthCm") or DEFAULT_UNKNOWN_PRODUCT["widthCm"]), 2
        )
        payload["heightCm"] = round(
            float(existing.get("heightCm") or DEFAULT_UNKNOWN_PRODUCT["heightCm"]), 2
        )

    if has_case_weight:
        payload["weightKg"] = round(float(research.get("weightKg") or 0), 2)
    else:
        payload["researchSuggestedWeightKg"] = round(
            float(research.get("weightKg") or 0), 2
        )
        payload["weightKg"] = round(
            float(existing.get("weightKg") or DEFAULT_UNKNOWN_PRODUCT["weightKg"]), 2
        )
    db.collection("products").document(clean_sku).set(payload, merge=True)


def get_products_by_skus(skus: list[str]) -> dict[str, dict[str, Any]]:
    lookup: dict[str, dict[str, Any]] = {}
    for sku in {str(item).strip().upper() for item in skus if str(item).strip()}:
        product = get_product_by_sku(sku)
        if product:
            lookup[sku] = product
    return lookup


def ensure_product_exists(
    sku: str,
    name: str,
    second_name: str | None = None,
    *,
    alternate_skus: list[str] | None = None,
    category: str = "",
    cost: float = 0.0,
    sale_price: float = 0.0,
    units_per_case: int = 1,
    source: str = "invoice_auto_create",
) -> bool:
    db = get_firestore_client()
    sku = str(sku).strip().upper()
    if get_product_by_sku(sku):
        return False

    payload = {
        **DEFAULT_UNKNOWN_PRODUCT,
        "sku": sku,
        "name": name,
        "secondName": second_name,
        "alternateSkus": sorted(
            {
                str(item).strip().upper()
                for item in (alternate_skus or [])
                if str(item).strip()
            }
        ),
        "category": category,
        "cost": round(float(cost or 0), 2),
        "salePrice": round(float(sale_price or 0), 2),
        "unitsPerCase": max(1, int(units_per_case or 1)),
        "createdAt": firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "source": source,
    }

    db.collection("products").document(sku).set(
        payload,
        merge=True,
    )
    return True


def create_scanned_catalog_product_if_missing(product: dict[str, Any]) -> bool:
    sku = str(product.get("sku") or "").strip().upper()
    description = str(product.get("description") or "").strip()
    if not sku or not description or get_product_by_sku(sku):
        return False

    payload = {
        **DEFAULT_UNKNOWN_PRODUCT,
        "sku": sku,
        "name": description,
        "secondName": str(product.get("secondName") or "").strip() or None,
        "category": str(product.get("category") or "Otro").strip() or "Otro",
        "brand": str(product.get("brand") or "").strip() or None,
        "manufacturer": str(product.get("manufacturer") or "").strip() or None,
        "packDescription": str(product.get("packDescription") or "").strip() or None,
        "unitsPerCase": max(1, int(product.get("unitsPerCase") or 1)),
        "alternateSkus": sorted(
            {
                str(value).strip().upper()
                for value in product.get("alternateSkus", [])
                if str(value).strip() and str(value).strip().upper() != sku
            }
        ),
        "barcode": str(product.get("barcode") or "").strip() or None,
        "color": str(product.get("color") or "").strip() or None,
        "material": str(product.get("material") or "").strip() or None,
        "size": str(product.get("size") or "").strip() or None,
        "source": "product_catalog_scan",
        "createdAt": firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    get_firestore_client().collection("products").document(sku).set(payload)
    return True


def upsert_products(products: list[dict[str, Any]]) -> int:
    db = get_firestore_client()
    batch = db.batch()
    count = 0
    for product in products:
        sku = str(product["sku"]).upper()
        doc_ref = db.collection("products").document(sku)
        payload = dict(product)
        payload["sku"] = sku
        payload["createdAt"] = firestore.SERVER_TIMESTAMP
        batch.set(doc_ref, payload, merge=True)
        count += 1

    if count > 0:
        batch.commit()
    return count
