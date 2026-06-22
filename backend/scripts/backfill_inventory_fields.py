from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from firebase_admin import firestore  # noqa: E402

from app.services.firebase_service import get_firestore_client  # noqa: E402


def _to_int(value: Any, default: int) -> int:
    if isinstance(value, bool):
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def main() -> None:
    db = get_firestore_client()
    docs = list(db.collection('products').stream())
    checked = 0
    updated = 0

    for doc in docs:
        checked += 1
        data = doc.to_dict() or {}
        patch: dict[str, Any] = {}

        stock_qty = _to_int(data.get('stockQty'), 0)
        if data.get('stockQty') != stock_qty:
            patch['stockQty'] = stock_qty

        units_per_case = max(1, _to_int(data.get('unitsPerCase'), 1))
        if data.get('unitsPerCase') != units_per_case:
            patch['unitsPerCase'] = units_per_case

        product_status = str(data.get('productStatus') or '').strip()
        if not product_status:
            patch['productStatus'] = 'activo'

        sku = str(data.get('sku') or doc.id).strip().upper()
        if data.get('sku') != sku:
            patch['sku'] = sku

        if patch:
            patch['updatedAt'] = firestore.SERVER_TIMESTAMP
            doc.reference.set(patch, merge=True)
            updated += 1

    print(f'Productos revisados: {checked}')
    print(f'Productos actualizados: {updated}')


if __name__ == '__main__':
    main()
