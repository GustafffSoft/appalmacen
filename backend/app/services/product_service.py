from __future__ import annotations

from app.models.schemas import DetectedItem
from app.services.firebase_service import get_product_by_sku

# Dimensions are now stored/processed in inches.
SEED_PRODUCTS: list[dict[str, object]] = [
    {"sku": "8J8", "name": "Dart foam cup 8 oz (1000/case)", "lengthCm": 30.5, "widthCm": 17.8, "heightCm": 11.7, "weightKg": 3.2},
    {"sku": "8FTL", "name": "Dart Lift-n-Lock lid 8 oz (1000/case)", "lengthCm": 16.8, "widthCm": 7.0, "heightCm": 13.5, "weightKg": 2.2},
    {"sku": "SOUP12", "name": "Plastic soup spoon medium (1000/case)", "lengthCm": 15.9, "widthCm": 10.2, "heightCm": 7.5, "weightKg": 3.1},
    {"sku": "FORK10", "name": "Plastic fork medium duty (1000/case)", "lengthCm": 16.1, "widthCm": 10.6, "heightCm": 7.9, "weightKg": 3.4},
    {"sku": "KNF10", "name": "Plastic knife medium duty (1000/case)", "lengthCm": 16.1, "widthCm": 10.6, "heightCm": 7.9, "weightKg": 3.3},
    {"sku": "PLT9", "name": "Foam plate 9 inch (500/case)", "lengthCm": 18.9, "widthCm": 18.9, "heightCm": 12.6, "weightKg": 4.8},
    {"sku": "BOWL12", "name": "Foam bowl 12 oz (500/case)", "lengthCm": 21.3, "widthCm": 15.0, "heightCm": 11.8, "weightKg": 4.2},
    {"sku": "NAP-DIN", "name": "Dinner napkin 2-ply (3000/case)", "lengthCm": 19.3, "widthCm": 13.0, "heightCm": 10.6, "weightKg": 5.3},
    {"sku": "PACT-11P", "name": "Pactiv 11P Meat Foam Tray", "lengthCm": 24.0, "widthCm": 16.0, "heightCm": 12.0, "weightKg": 4.5},
    {"sku": "PACT-MM", "name": "Pactiv ClearView MealMaster", "lengthCm": 24.0, "widthCm": 16.0, "heightCm": 14.0, "weightKg": 6.5},
    {"sku": "ROAST-GR", "name": "Roaster Grande Black Base / Clear Dome Lid", "lengthCm": 26.0, "widthCm": 18.0, "heightCm": 16.0, "weightKg": 8.5},
    {"sku": "RPET-35", "name": "35 oz RPET Clear Hinged Container", "lengthCm": 24.0, "widthCm": 20.0, "heightCm": 14.0, "weightKg": 10.0},
    {"sku": "HFA-FULL", "name": "HFA Full Size Steam Table Pan", "lengthCm": 21.0, "widthCm": 13.0, "heightCm": 13.0, "weightKg": 5.25},
    {"sku": "HFA-HALF", "name": "HFA Half Size Steam Table Pan", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 12.0, "weightKg": 4.25},
    {"sku": "HFA-LID", "name": "HFA Foil Lids", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 8.0, "weightKg": 2.75},
    {"sku": "FOAM-9PL", "name": "Foam Plates 9\" (4/125)", "lengthCm": 20.0, "widthCm": 20.0, "heightCm": 12.0, "weightKg": 3.75},
    {"sku": "CLAM-FOAM", "name": "Foam Food Containers", "lengthCm": 24.0, "widthCm": 16.0, "heightCm": 16.0, "weightKg": 5.75},
    {"sku": "VINYL-XL", "name": "Vinyl Gloves XL", "lengthCm": 16.0, "widthCm": 12.0, "heightCm": 10.0, "weightKg": 5.25},
    {"sku": "REDDI-BAG", "name": "Get Reddi Food Storage Bags", "lengthCm": 14.0, "widthCm": 10.0, "heightCm": 8.0, "weightKg": 3.5},
    {"sku": "CUBAN-BAG", "name": "Cuban Bread Bags", "lengthCm": 16.0, "widthCm": 12.0, "heightCm": 10.0, "weightKg": 4.25},
    {"sku": "CAN-LINER", "name": "Can Liners", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 12.0, "weightKg": 11.0},
    {"sku": "INTER-NAP", "name": "Right Choice Interfold Napkins", "lengthCm": 20.0, "widthCm": 14.0, "heightCm": 12.0, "weightKg": 9.5},
    {"sku": "LITE-DRI", "name": "Lite-Dri Meat Pads", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 12.0, "weightKg": 5.75},
    {"sku": "SKY-SPNG", "name": "Skyline Scrubbing Sponge", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 10.0, "weightKg": 3.5},
    {"sku": "KRAFT-HND", "name": "Kraft Paper Shopping Bags", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 14.0, "weightKg": 8.0},
    {"sku": "PUREX-BLC", "name": "Purex Bleach", "lengthCm": 16.0, "widthCm": 12.0, "heightCm": 12.0, "weightKg": 17.0},
    {"sku": "936818", "name": "QDART16MJ20 - Dart 16 oz Soup Foam Container - Case Pack 500", "lengthCm": 24.0, "widthCm": 16.0, "heightCm": 14.0, "weightKg": 5.1},
    {"sku": "936841", "name": "QPLAS11412 - Lid 8 oz & 16 oz Foam Soup Container - 1000 Case Pack", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 10.0, "weightKg": 3.1},
    {"sku": "936833", "name": "QDART32MJ48 - Dart 32 oz Soup Foam Container - Case Pack 500", "lengthCm": 24.0, "widthCm": 16.0, "heightCm": 16.0, "weightKg": 6.0},
    {"sku": "936819", "name": "QDART48JL - Dart 32 oz Soup Foam Container Vented Lid - Case Pack 500", "lengthCm": 18.0, "widthCm": 12.0, "heightCm": 9.0, "weightKg": 3.4},
]


def resolve_detected_items(order_items: list[dict[str, int]]) -> list[DetectedItem]:
    detected: list[DetectedItem] = []

    for index, item in enumerate(order_items, start=1):
        sku = str(item.get("sku", "")).strip()
        qty = int(item.get("qty", 1))
        if not sku or qty <= 0:
            continue

        product = get_product_by_sku(sku)
        if not product:
            detected.append(
                DetectedItem(
                    boxId=f"b{index}",
                    sku=sku,
                    name=f"Unknown product {sku}",
                    lengthCm=16,
                    widthCm=12,
                    heightCm=12,
                    weightKg=10,
                    qty=qty,
                )
            )
            continue

        detected.append(
            DetectedItem(
                boxId=f"b{index}",
                sku=sku,
                name=str(product.get("name", sku)),
                lengthCm=float(product.get("lengthCm", 16)),
                widthCm=float(product.get("widthCm", 12)),
                heightCm=float(product.get("heightCm", 12)),
                weightKg=float(product.get("weightKg", 10)),
                qty=qty,
            )
        )

    return detected
