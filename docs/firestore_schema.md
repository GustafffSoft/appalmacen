# Firestore Schema

## products

Documento (`id` recomendado = `sku`):
- `sku` (string)
- `name` (string)
- `lengthCm` (number) -> largo de caja master
- `widthCm` (number)
- `heightCm` (number)
- `weightKg` (number)
- `imageRef` (string opcional)
- `createdAt` (timestamp)

## orders

Documento:
- `status` (`new` | `uploaded` | `processing` | `processed` | `error`)
- `createdAt` (timestamp)
- `updatedAt` (timestamp)
- `imagePath` (string)
- `imageUrl` (string)
- `items` (array requerido para flujo actual):
  - `{ sku, qty }`
- `errorMessage` (string opcional)

## pallet_plans

Documento con id = `orderId`:
- `orderId`
- `status`
- `identificationMode`
- `allowOverhangCm`
- `createdAt`
- `pallet`: `{ lengthCm, widthCm, maxHeightCm, maxWeightKg }`
- `boxes`: `{ boxId, sku, name, lengthCm, widthCm, heightCm, weightKg, qty }[]`
- `layout`: `{ boxId, x, y, z, rotation, layer }[]`
- `stats`: `{ totalWeightKg, usedVolumeCm3, utilizationPct, unpackedCount }`