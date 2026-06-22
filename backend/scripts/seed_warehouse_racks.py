from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from firebase_admin import firestore  # noqa: E402

from app.services.firebase_service import get_firestore_client  # noqa: E402


DEFAULT_RACKS = [
    {'rackId': 'RACK-A', 'name': 'Rack A', 'levels': 3, 'positionsPerLevel': 4},
    {'rackId': 'RACK-B', 'name': 'Rack B', 'levels': 3, 'positionsPerLevel': 4},
    {'rackId': 'RACK-C', 'name': 'Rack C', 'levels': 3, 'positionsPerLevel': 4},
]


def main() -> None:
    db = get_firestore_client()
    created = 0
    for rack in DEFAULT_RACKS:
        ref = db.collection('warehouse_racks').document(rack['rackId'])
        if ref.get().exists:
            continue
        ref.set(
            {
                **rack,
                'createdAt': firestore.SERVER_TIMESTAMP,
                'updatedAt': firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        created += 1

    print(f'Racks creados: {created}')


if __name__ == '__main__':
    main()
