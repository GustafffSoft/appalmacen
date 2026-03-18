from __future__ import annotations

import json
from datetime import datetime

from app.core.config import get_settings
from app.models.schemas import RegisterInvoiceRequest, RegisterInvoiceResponse, ScanInvoicePagesRequest, ScanInvoicePagesResponse
from app.services.firebase_service import (
    ensure_product_exists,
    get_invoice,
    get_products_by_skus,
    save_invoice_record,
    upsert_order_from_invoice,
)
from app.services.image_service import download_image
from app.services.invoice_parser_service import parse_invoice_texts
from app.services.ocr_service import OcrUnavailableError, extract_text_from_image


def _normalize_items(items: list[dict]) -> list[dict]:
    return sorted(
        [
            {
                'sku': str(item['sku']).strip().upper(),
                'description': str(item['description']).strip(),
                'qty': int(item['qty']),
                'rate': round(float(item.get('rate', 0)), 2),
                'amount': round(float(item.get('amount', 0)), 2),
            }
            for item in items
        ],
        key=lambda item: item['sku'],
    )


def _apply_catalog_matches(items: list[dict]) -> tuple[list[dict], list[str]]:
    if not items:
        return items, []

    catalog = get_products_by_skus([item['sku'] for item in items])
    matched_skus: list[str] = []
    normalized: list[dict] = []
    for item in items:
        sku = str(item['sku']).strip().upper()
        matched = catalog.get(sku)
        if matched:
            preferred_name = str(matched.get('name') or item['description']).strip()
            second_name = str(matched.get('secondName') or '').strip()
            item = {
                **item,
                'sku': sku,
                'description': preferred_name,
                'catalogName': preferred_name,
                'catalogSecondName': second_name,
            }
            matched_skus.append(sku)
        normalized.append(item)
    return normalized, matched_skus


def _build_diff(previous: dict, current_items: list[dict], current_page_count: int) -> list[str]:
    diff: list[str] = []
    prev_items = _normalize_items(previous.get('items', [])) if previous else []
    prev_by_sku = {item['sku']: item for item in prev_items}
    curr_by_sku = {item['sku']: item for item in current_items}

    for sku, item in curr_by_sku.items():
        prev = prev_by_sku.get(sku)
        if prev is None:
            diff.append(f'SKU {sku} agregado con qty {item["qty"]}.')
        elif prev['qty'] != item['qty']:
            diff.append(f'SKU {sku} cambio de qty {prev["qty"]} a {item["qty"]}.')
        elif prev['description'] != item['description']:
            diff.append(f'SKU {sku} cambio descripcion detectada.')

    for sku in prev_by_sku:
        if sku not in curr_by_sku:
            diff.append(f'SKU {sku} fue removido del invoice.')

    prev_page_count = int(previous.get('pageCount', 0)) if previous else 0
    if previous and prev_page_count != current_page_count:
        diff.append(f'Cantidad de paginas cambio de {prev_page_count} a {current_page_count}.')

    return diff


def _evaluate_invoice_status(items: list[dict], store_number: str | None, address: str | None) -> tuple[bool, bool]:
    has_store_reference = bool((store_number or '').strip() or (address or '').strip())
    is_complete = bool(items) and has_store_reference
    return is_complete, True


def _write_scan_debug_log(*, invoice_number: str | None, page_count: int, extracted_texts: list[str], parsed: dict, message: str) -> None:
    settings = get_settings()
    timestamp = datetime.now().isoformat(timespec='seconds')
    payload = {
        'timestamp': timestamp,
        'invoiceNumberRequested': invoice_number,
        'pageCount': page_count,
        'message': message,
        'parsedSummary': {
            'invoiceNumber': parsed.get('invoiceNumber'),
            'invoiceDate': parsed.get('invoiceDate'),
            'storeNumber': parsed.get('storeNumber'),
            'storeName': parsed.get('storeName'),
            'address': parsed.get('address'),
            'itemCount': len(parsed.get('items', [])),
            'catalogMatchedSkus': parsed.get('catalogMatchedSkus', []),
            'items': parsed.get('items', []),
        },
        'rawLines': parsed.get('rawLines', []),
        'ocrTexts': extracted_texts,
    }

    latest_path = settings.log_dir / 'invoice_scan_latest.json'
    history_path = settings.log_dir / 'invoice_scan_history.log'
    latest_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding='utf-8')
    with history_path.open('a', encoding='utf-8') as history_file:
        history_file.write(json.dumps(payload, ensure_ascii=False))
        history_file.write('\n')



def scan_invoice_pages(request: ScanInvoicePagesRequest) -> ScanInvoicePagesResponse:
    texts: list[str] = []
    try:
        for page in request.pages:
            if not page.imageUrl:
                texts.append('')
                continue
            local_path = download_image(page.imageUrl)
            texts.append(extract_text_from_image(local_path))
    except OcrUnavailableError as exc:
        _write_scan_debug_log(
            invoice_number=request.invoiceNumber,
            page_count=len(request.pages),
            extracted_texts=texts,
            parsed={},
            message=str(exc),
        )
        return ScanInvoicePagesResponse(
            ocrAvailable=False,
            parserMatched=False,
            isComplete=False,
            totalsMatch=False,
            message=str(exc),
            extractedTexts=texts,
            suggestedInvoice={},
        )

    parsed = parse_invoice_texts(texts, request.invoiceNumber)
    matched_items, matched_skus = _apply_catalog_matches(parsed.get('items', []))
    parsed['items'] = matched_items
    parsed['catalogMatchedSkus'] = matched_skus

    item_count = len(parsed.get('items', []))
    store_ref = parsed.get('storeNumber') or parsed.get('address')
    if item_count:
        catalog_note = f' Catalogo aplicado a {len(matched_skus)} SKU.' if matched_skus else ''
        message = (
            f'OCR ejecutado. Se detectaron {item_count} lineas y referencia de tienda: '
            f'{"si" if store_ref else "no"}.{catalog_note} Revisa los datos antes de registrar.'
        )
    else:
        message = 'OCR ejecutado, pero no se detectaron lineas confiables.'

    _write_scan_debug_log(
        invoice_number=request.invoiceNumber,
        page_count=len(request.pages),
        extracted_texts=texts,
        parsed=parsed,
        message=message,
    )

    return ScanInvoicePagesResponse(
        ocrAvailable=True,
        parserMatched=bool(parsed.get('items')),
        isComplete=bool(parsed.get('isComplete')),
        totalsMatch=bool(parsed.get('totalsMatch')),
        message=message,
        extractedTexts=texts,
        suggestedInvoice=parsed,
    )



def register_invoice(request: RegisterInvoiceRequest) -> RegisterInvoiceResponse:
    previous = get_invoice(request.invoiceNumber)
    normalized_items = _normalize_items([item.model_dump() for item in request.items])
    diff = _build_diff(previous, normalized_items, request.pageCount)
    is_complete, totals_match = _evaluate_invoice_status(normalized_items, request.storeNumber, request.address)

    new_products: list[str] = []
    for item in normalized_items:
        created = ensure_product_exists(item['sku'], item['description'])
        if created:
            new_products.append(item['sku'])

    status = 'updated' if previous else 'created'
    scan_status = 'updated' if diff else ('complete' if is_complete else 'partial')

    invoice_payload = {
        'invoiceDate': request.invoiceDate,
        'storeNumber': request.storeNumber,
        'storeName': request.storeName,
        'address': request.address,
        'subtotal': round(request.subtotal, 2),
        'tax': round(request.tax, 2),
        'total': round(request.total, 2),
        'pageCount': request.pageCount,
        'pages': [page.model_dump() for page in request.pages],
        'items': normalized_items,
        'sourceMode': request.sourceMode,
        'scanStatus': scan_status,
        'invoiceDiff': diff,
        'linesAmountTotal': 0.0,
        'totalsMatch': totals_match,
        'isComplete': is_complete,
    }
    save_invoice_record(request.invoiceNumber, invoice_payload)

    order_payload = {
        'status': 'new',
        'invoiceNumber': request.invoiceNumber,
        'invoiceDate': request.invoiceDate,
        'storeNumber': request.storeNumber,
        'storeName': request.storeName,
        'address': request.address,
        'subtotal': 0.0,
        'tax': 0.0,
        'total': 0.0,
        'pageCount': request.pageCount,
        'invoiceDiff': diff,
        'isComplete': is_complete,
        'totalsMatch': totals_match,
        'items': [
            {
                'sku': item['sku'],
                'qty': item['qty'],
                'description': item['description'],
                'rate': 0.0,
                'amount': 0.0,
            }
            for item in normalized_items
        ],
    }
    order_id, created_order = upsert_order_from_invoice(request.invoiceNumber, order_payload)

    return RegisterInvoiceResponse(
        invoiceNumber=request.invoiceNumber,
        status=status,
        orderId=order_id,
        createdOrder=created_order,
        updatedInvoice=bool(previous),
        isComplete=is_complete,
        totalsMatch=totals_match,
        newProductsCreated=new_products,
        invoiceDiff=diff,
    )
