from app.models.schemas import DetectedItem


def detect_items(_image_path: str) -> list[DetectedItem]:
    # Placeholder output until YOLO model is integrated with real detections.
    return [
        DetectedItem(
            boxId="b1",
            sku="SKU-CAJA-001",
            name="Caja chica",
            lengthCm=40,
            widthCm=30,
            heightCm=20,
            weightKg=8,
            qty=2,
        ),
        DetectedItem(
            boxId="b2",
            sku="SKU-CAJA-002",
            name="Caja mediana",
            lengthCm=60,
            widthCm=40,
            heightCm=30,
            weightKg=15,
            qty=1,
        ),
        DetectedItem(
            boxId="b3",
            sku="SKU-CAJA-003",
            name="Caja alta",
            lengthCm=50,
            widthCm=35,
            heightCm=45,
            weightKg=18,
            qty=1,
        ),
    ]