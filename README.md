# AppAlmacen

Aplicacion Flutter + FastAPI + Firebase para crear ordenes, subir invoice y calcular layout de pallet.

## Flujo actual

1. Home -> `Cargar Catalogo Base` (siembra productos en Firestore).
2. `Crear Orden` -> seleccionar SKUs y cantidades.
3. En detalle de orden -> subir imagen del invoice.
4. `Procesar Pallet` -> backend identifica items de la orden y calcula packing.
5. Ver resultado + 4 vistas del pallet (Top/Front/Right/Back).

## Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
```

Agregar credencial Firebase:
- Guardar `serviceAccountKey.json` en `backend/serviceAccountKey.json`.
- Verificar en `.env`: `GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json`.

Ejecutar backend:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_backend.ps1
```

## Mobile

```powershell
cd mobile_app
flutter pub get
flutter run
```

Para telefono fisico: `mobile_app/lib/config.dart` debe apuntar a tu IP LAN.

## API util para seed

Con backend corriendo:
- `POST http://<ip>:8000/api/v1/products/seed`

## Nota de datos de productos

- 8J8 y 8FTL tienen medidas/pesos aproximados basados en fichas publicas.
- El resto del catalogo son aproximaciones operativas para pruebas iniciales.