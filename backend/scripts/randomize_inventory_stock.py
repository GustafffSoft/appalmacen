from __future__ import annotations

import random
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
    random.seed(20260610)
    db = get_firestore_client()
    docs = list(db.collection('products').stream())
    updated = 0

    for doc in docs:
        data = doc.to_dict() or {}
        current_units = max(1, _to_int(data.get('unitsPerCase'), 1))
        stock_qty = random.randint(1, 120)
        if random.random() < 0.25:
            stock_qty = random.randint(1, 8)

        product_status = 'bajo_stock' if stock_qty <= 8 else 'activo'
        doc.reference.set(
            {
                'stockQty': stock_qty,
                'unitsPerCase': current_units,
                'productStatus': product_status,
                'updatedAt': firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        updated += 1

    print(f'Productos actualizados con existencia aleatoria: {updated}')


if __name__ == '__main__':
    main()
