from __future__ import annotations

from app.services.firebase_service import get_order
from app.services.product_service import resolve_detected_items


def identify_products_from_invoice(order_id: str, _image_path: str) -> tuple[str, list]:
    order_doc = get_order(order_id)
    order_items = order_doc.get("items") or []

    if order_items:
        return "order_items", resolve_detected_items(order_items)

    # Placeholder until OCR/ML extraction from invoice is integrated.
    return "invoice_placeholder", []