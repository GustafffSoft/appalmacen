# AI Sales & Supply System

Este documento define la ruta recomendada para convertir AppAlmacen en un sistema de ventas B2B y compras inteligentes para supplies de restaurantes.

## Objetivo

Crear una herramienta que ayude al almacen a:

- Registrar productos, clientes, suplidores, costos y precios.
- Encontrar prospectos como restaurantes, cafeterias, delis, food trucks y bakeries.
- Comparar costos de suplidores antes de comprar.
- Calcular margen y precio recomendado.
- Preparar mensajes de venta personalizados.
- Dar seguimiento a oportunidades sin hacer spam masivo.

## Arquitectura recomendada

### App

- Flutter para mobile/web.
- Firebase Auth anonimo para acceso rapido.
- Firestore como base operativa inicial.
- Firebase Storage para invoices e imagenes.

### Backend

- FastAPI para procesos pesados: OCR, parsing de invoice, pallet layout y futuros agentes.
- Firestore Admin SDK para leer/escribir datos desde servicios automatizados.

### Agentes futuros

- OpenAI API para razonamiento, clasificacion y generacion de mensajes.
- Google Places API para buscar prospectos por zona.
- n8n para automatizaciones despues de tener datos limpios.
- WhatsApp Business API o email para seguimiento semi-automatizado.

## Dashboard operativo

La pantalla principal resume:

- Productos bajo stock.
- Mejores compras segun menor costo por unidad.
- Seguimientos pendientes.
- Mensajes de venta listos como borrador.

## Escaneo de invoices con IA

El flujo de `Escanear Invoice` usa:

- OCR para extraer texto de las fotos.
- OpenAI para estructurar lineas de producto desde el texto OCR.
- Creacion automatica de productos nuevos en `products` cuando el SKU no existe.
- Categoria, costo detectado y unidades por caja cuando la IA puede inferirlos.
- Fallback al parser local si la IA no esta disponible.

## Colecciones principales

### products

Catalogo de productos del almacen.

Campos clave:

- `sku`
- `name`
- `secondName`
- `lengthCm`
- `widthCm`
- `heightCm`
- `weightKg`
- `cost`
- `salePrice`
- `stockQty`

### prospects

Clientes potenciales y clientes B2B.

Campos clave:

- `businessName`
- `businessType`
- `phone`
- `email`
- `address`
- `area`
- `likelyProducts`
- `status`
- `notes`

Estados recomendados:

- `nuevo`
- `contactado`
- `interesado`
- `cliente`
- `pausado`

### suppliers

Suplidores, mayoristas o tiendas donde se puede comprar mercancia.

Campos clave:

- `name`
- `contact`
- `phone`
- `website`
- `productFocus`
- `paymentTerms`
- `notes`

### supplier_prices

Precios por producto y suplidor.

Campos clave:

- `supplierId`
- `sku`
- `caseCost`
- `shippingCost`
- `unitsPerCase`
- `unitCost`
- `minimumOrderQty`
- `sourceUrl`
- `lastCheckedAt`

Estado inicial:

- La app registra precios por suplidor desde Flutter.
- Calcula `totalCost` como costo por caja + shipping.
- Calcula `unitCost` usando unidades por caja.
- Marca como mejor precio el menor costo por unidad para cada SKU.

## Fases

### Fase 1: Base comercial

Estado actual inicial:

- Productos existentes.
- Productos con categoria, costo, precio de venta, stock, unidades por caja, margen y estado comercial.
- Ordenes e invoices existentes.
- Nuevo modulo de clientes B2B.
- Nuevo modulo de suplidores.
- Nueva calculadora de margen.
- Nuevo modulo de precios por suplidor con comparacion automatica.

Siguiente paso:

- Conectar agente que sugiera compra y precio de reventa usando precios reales.

### Fase 2: Agente buscador de clientes

Entrada:

- Zona.
- Tipo de negocio.
- Producto a vender.

Salida:

- Lista de prospectos.
- Productos probables.
- Mensaje sugerido.
- Prioridad de contacto.

### Fase 3: Agente vendedor

Funciones:

- Crear mensajes para WhatsApp, SMS o email.
- Personalizar por tipo de negocio.
- Guardar historial de contacto.
- Sugerir siguiente accion.

Estado inicial:

- La app genera mensajes desde cliente + productos seleccionados.
- Soporta español e ingles.
- Soporta tono por canal: WhatsApp, SMS, email o llamada.
- Guarda el mensaje como borrador en `sales_messages`.
- Permite seguimiento con estado, notas y fecha de proximo contacto.
- Puede usar IA real via FastAPI + OpenAI Responses API cuando `OPENAI_API_KEY` existe en `backend/.env`.

Regla importante:

- El envio debe ser semi-automatico y aprobado por una persona.

### Fase 4: Agente de suplidores

Funciones:

- Comparar precio por caja.
- Calcular shipping.
- Calcular costo por unidad.
- Recomendar si conviene comprar.
- Alertar cuando baja un precio.

Estado inicial:

- La app compara precios por suplidor y selecciona el menor costo por unidad.
- Recomienda compra cuando el stock es bajo.
- Calcula margen estimado usando mejor costo de suplidor y precio de venta.
- Sugiere precio de venta con markup de 30%.

### Fase 5: Inventario y rutas

Funciones:

- Productos lentos y rapidos.
- Recomendacion de compra.
- Agrupacion de entregas por zona.
- Reportes semanales.
