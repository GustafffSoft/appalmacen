from __future__ import annotations

from firebase_admin import firestore

from app.services.firebase_service import get_firestore_client


CANONICAL_PRODUCTS = {
    '936839': {
        'name': 'Plastifar 3/4 oz plastic cup (5,000 cs pk) Cuban coffee cup',
        'alternateSkus': ['QPLAS11014'],
    },
    '936799': {
        'name': 'Dart 12J12 Foam Cup WHT 12 oz - Case Pack 1,000',
        'alternateSkus': ['QDART12J12'],
    },
    '936807': {
        'name': '16J16 Dart 16 oz Foam Cup WHT - Case Pack 1,000',
        'alternateSkus': ['QDART16J16'],
    },
    '936833': {
        'name': 'Dart 32 oz Soup Foam Container - Case Pack 500',
        'alternateSkus': ['QDART32MJ48'],
    },
    '936798': {
        'name': 'Dart 8FTL Lift N Lock Lid - Case Pack 1,000',
        'alternateSkus': ['QDART8FTL'],
    },
    '936819': {
        'name': 'Dart 32 oz Soup Foam Container Vented Lid - Case Pack 500',
        'alternateSkus': ['QDART48JL'],
    },
    '969276': {
        'name': 'Aluminum Foil Roll 18" x 1000\' Heavy Duty',
        'alternateSkus': ['Q18X1000HD'],
    },
    '936830': {
        'name': 'QPLAS13185 - Foam Bowl Container 8 oz Squat - 1000/Case',
        'alternateSkus': ['QPLAS13185'],
    },
    '936841': {
        'name': 'QPLAS11412 - Lid 8 oz & 16 oz Foam Soup Container - 1000 Case Pack',
        'alternateSkus': ['QPLAS11412'],
    },
    '969314': {
        'name': 'Q31HWPH50B - 3PCS Cutlery Kit HW Black - 500/Case',
        'alternateSkus': ['Q31HWPH50B'],
    },
}

OBSOLETE_SKUS = {
    'PLAS! 1014',
    'QPLAS11014',
    'T12J12',
    'QDART12J12',
    '16',
    'QDART16316',
    'QDART16J16',
    'QDART32MIJ48',
    'QDART32MJ48',
    'DARTS8FTL',
    'QDART8FTL',
    'QDARTSFTL',
    'QDART48JL',
    'Q18X 1000HD',
    'Q18X1000HD',
    'QPLAS13185',
    'HWPHSOB',
    'Q31HWPHSOB',
}


def main() -> None:
    db = get_firestore_client()
    products = db.collection('products')

    for sku, payload in CANONICAL_PRODUCTS.items():
        products.document(sku).set(
            {
                'sku': sku,
                **payload,
                'updatedAt': firestore.SERVER_TIMESTAMP,
                'source': 'invoice_consolidation',
            },
            merge=True,
        )
        print(f'upserted {sku}')

    for sku in sorted(OBSOLETE_SKUS):
        snap = products.document(sku).get()
        if not snap.exists:
            continue
        data = snap.to_dict() or {}
        if data.get('source') != 'invoice_ai_auto_create':
            print(f'skipped {sku} source={data.get("source")!r}')
            continue
        products.document(sku).delete()
        print(f'deleted {sku}')


if __name__ == '__main__':
    main()
