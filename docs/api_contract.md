# API Contract

Base path: `/api/v1`

## GET /health

Response:
```json
{ "status": "ok" }
```

## POST /products/seed

Carga catalogo base de productos supply en Firestore.

Response:
```json
{
  "inserted": 8,
  "skus": ["8J8", "8FTL", "SOUP12", "FORK10", "KNF10", "PLT9", "BOWL12", "NAP-DIN"]
}
```

## GET /products

Lista catalogo de productos.

## POST /orders/{orderId}/process

Body:
```json
{
  "imageUrl": "https://firebasestorage.googleapis.com/...",
  "allowOverhangCm": 0,
  "pallet": {
    "lengthCm": 120,
    "widthCm": 100,
    "maxHeightCm": 180,
    "maxWeightKg": 900
  }
}
```

Response:
```json
{
  "orderId": "...",
  "status": "processed",
  "identificationMode": "order_items",
  "allowOverhangCm": 0,
  "pallet": {"lengthCm":120,"widthCm":100,"maxHeightCm":180,"maxWeightKg":900},
  "boxes": [...],
  "layout": [...],
  "stats": {
    "totalWeightKg": 0,
    "usedVolumeCm3": 0,
    "utilizationPct": 0,
    "unpackedCount": 0
  }
}
```