# AppAlmacen

Aplicacion Flutter + FastAPI + Firebase para crear ordenes, subir invoice y calcular layout de pallet.

## Flujo actual

1. Home -> `Cargar Catalogo Base` (siembra productos en Firestore).
2. `Crear Orden` -> seleccionar SKUs y cantidades.
3. En detalle de orden -> subir imagen del invoice.
4. `Procesar Pallet` -> backend identifica items de la orden y calcula packing.
5. Ver resultado + 4 vistas del pallet (Top/Front/Right/Back).

## Modulo comercial B2B

La app ya incluye una primera base para ventas y compras de supplies:

- `Dashboard`: resumen diario con bajo stock, mejores compras, seguimientos y mensajes listos.
- `Escanear Invoice con IA`: OCR + OpenAI detectan lineas de invoice y crean productos nuevos en catalogo.
- `Clientes B2B`: prospectos, tipo de negocio, telefono, zona, productos probables y estado.
- `Suplidores`: mayoristas, contactos, productos principales, terminos y notas.
- `Precios por Suplidor`: costo por caja, shipping, unidades por caja, minimo de compra y mejor costo por unidad.
- `Recomendacion de Compra`: mejor suplidor por SKU, margen estimado, venta sugerida y alerta de stock.
- `Agente Vendedor`: genera mensajes para clientes B2B por WhatsApp, SMS, email o llamada.
- `Seguimiento`: cambia estados de mensajes, agrega notas y fecha de proximo contacto.
- `Calculadora de Margen`: costo, shipping, unidades por caja, precio de venta, ganancia y margen.
- `Productos`: categoria, costo, precio de venta, stock, unidades por caja, margen y estado comercial.

La ruta completa para agentes esta documentada en `docs/ai_sales_supply_system.md`.

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

Para activar IA real en `Agente Vendedor`, agregar en `backend/.env`:

```powershell
OPENAI_API_KEY=sk-tu-api-key
OPENAI_MODEL=gpt-5.2
```

Ejecutar backend:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_backend.ps1
```

Para probar Flutter web contra backend local:

```powershell
cd mobile_app
flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8000
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
