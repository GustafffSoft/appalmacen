from __future__ import annotations

from pathlib import Path
from typing import Any

import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.core.config import get_settings

_firestore_client: firestore.Client | None = None
DEFAULT_UNKNOWN_PRODUCT = {
    'lengthCm': 16.0,
    'widthCm': 12.0,
    'heightCm': 12.0,
    'weightKg': 10.0,
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

    credentials_path = _resolve_credentials_path(settings.google_application_credentials)
    if not credentials_path.exists():
        raise RuntimeError(
            f"Firebase credentials file not found at {credentials_path}. "
            "Create backend/serviceAccountKey.json and set GOOGLE_APPLICATION_CREDENTIALS."
        )

    cred = credentials.Certificate(str(credentials_path))
    firebase_admin.initialize_app(
        cred,
        {
            'projectId': settings.firebase_project_id,
            'storageBucket': settings.firebase_storage_bucket,
        },
    )


def get_firestore_client() -> firestore.Client:
    global _firestore_client
    if _firestore_client is None:
        _init_firebase()
        _firestore_client = firestore.client()
    return _firestore_client


def update_order_status(order_id: str, status: str, extra: dict[str, Any] | None = None) -> None:
    db = get_firestore_client()
    payload: dict[str, Any] = {
        'status': status,
        'updatedAt': firestore.SERVER_TIMESTAMP,
    }
    if extra:
        payload.update(extra)
    db.collection('orders').document(order_id).set(payload, merge=True)


def save_pallet_plan(order_id: str, payload: dict[str, Any]) -> None:
    db = get_firestore_client()
    write_payload = dict(payload)
    write_payload['orderId'] = order_id
    write_payload['createdAt'] = firestore.SERVER_TIMESTAMP
    db.collection('pallet_plans').document(order_id).set(write_payload, merge=True)


def save_invoice_record(invoice_number: str, payload: dict[str, Any]) -> None:
    db = get_firestore_client()
    write_payload = dict(payload)
    write_payload['invoiceNumber'] = invoice_number
    write_payload['updatedAt'] = firestore.SERVER_TIMESTAMP
    if 'createdAt' not in write_payload:
        write_payload['createdAt'] = firestore.SERVER_TIMESTAMP
    db.collection('invoices').document(invoice_number).set(write_payload, merge=True)


def get_invoice(invoice_number: str) -> dict[str, Any]:
    db = get_firestore_client()
    snap = db.collection('invoices').document(invoice_number).get()
    return snap.to_dict() if snap.exists else {}


def get_order(order_id: str) -> dict[str, Any]:
    db = get_firestore_client()
    snap = db.collection('orders').document(order_id).get()
    return snap.to_dict() if snap.exists else {}


def get_order_by_invoice_number(invoice_number: str) -> tuple[str | None, dict[str, Any] | None]:
    db = get_firestore_client()
    query = db.collection('orders').where(filter=FieldFilter('invoiceNumber', '==', invoice_number)).limit(1).stream()
    for doc in query:
        return doc.id, doc.to_dict()
    return None, None


def upsert_order_from_invoice(invoice_number: str, payload: dict[str, Any]) -> tuple[str, bool]:
    db = get_firestore_client()
    order_id, _existing = get_order_by_invoice_number(invoice_number)
    created = False
    if order_id is None:
        doc_ref = db.collection('orders').document()
        order_id = doc_ref.id
        created = True
    else:
        doc_ref = db.collection('orders').document(order_id)

    doc_ref.set(payload, merge=True)
    return order_id, created


def list_products() -> list[dict[str, Any]]:
    db = get_firestore_client()
    docs = db.collection('products').stream()
    result: list[dict[str, Any]] = []
    for doc in docs:
        data = doc.to_dict()
        data['id'] = doc.id
        result.append(data)
    return result


def get_product_by_sku(sku: str) -> dict[str, Any] | None:
    db = get_firestore_client()
    doc = db.collection('products').document(str(sku).upper()).get()
    if doc.exists:
        return doc.to_dict()

    query = db.collection('products').where(filter=FieldFilter('sku', '==', str(sku).upper())).limit(1).stream()
    for row in query:
        return row.to_dict()
    return None


def get_products_by_skus(skus: list[str]) -> dict[str, dict[str, Any]]:
    lookup: dict[str, dict[str, Any]] = {}
    for sku in {str(item).strip().upper() for item in skus if str(item).strip()}:
        product = get_product_by_sku(sku)
        if product:
            lookup[sku] = product
    return lookup


def ensure_product_exists(sku: str, name: str, second_name: str | None = None) -> bool:
    db = get_firestore_client()
    sku = str(sku).strip().upper()
    if get_product_by_sku(sku):
        return False

    db.collection('products').document(sku).set(
        {
            'sku': sku,
            'name': name,
            'secondName': second_name,
            **DEFAULT_UNKNOWN_PRODUCT,
            'createdAt': firestore.SERVER_TIMESTAMP,
            'updatedAt': firestore.SERVER_TIMESTAMP,
            'source': 'invoice_auto_create',
        },
        merge=True,
    )
    return True


def upsert_products(products: list[dict[str, Any]]) -> int:
    db = get_firestore_client()
    batch = db.batch()
    count = 0
    for product in products:
        sku = str(product['sku']).upper()
        doc_ref = db.collection('products').document(sku)
        payload = dict(product)
        payload['sku'] = sku
        payload['createdAt'] = firestore.SERVER_TIMESTAMP
        batch.set(doc_ref, payload, merge=True)
        count += 1

    if count > 0:
        batch.commit()
    return count
