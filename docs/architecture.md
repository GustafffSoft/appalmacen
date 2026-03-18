# Architecture

## UX and flow

1. Home screen
- Cargar catalogo base (seed de productos de supply).
- Crear nueva orden.
- Listar ordenes con estado.

2. Create Order screen
- Seleccionar productos por SKU.
- Ajustar cantidades.
- Guardar orden en Firestore con `items`.

3. Order Detail screen
- Subir imagen del invoice a Storage.
- Procesar orden en backend.
- Ver stats y 4 vistas del pallet: Top, Front, Right, Back.

## Backend pipeline

1. `POST /api/v1/products/seed`
- Inserta catalogo inicial en Firestore (`products`).

2. `POST /api/v1/orders/{orderId}/process`
- Descarga invoice desde URL.
- Identifica productos con modulo `invoice_identification_service`.
- Resolucion actual: usa `orders/{orderId}.items` y mapea SKU a `products`.
- Ejecuta palletizing (`py3dbp`) sin overhang (0 cm).
- Guarda resultado en `pallet_plans/{orderId}`.

## Pallet constraints

- Pallet estandar por defecto: `120 x 100 x 180 cm`, `900 kg`.
- Overhang forzado a `0` en el flujo actual para no salir del pallet.
- Layout guardado con `x, y, z, rotation, layer`.