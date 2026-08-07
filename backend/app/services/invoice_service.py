from __future__ import annotations

import json
import re
from datetime import datetime
from difflib import SequenceMatcher
from time import perf_counter

from app.core.config import get_settings
from app.models.schemas import RegisterInvoiceRequest, RegisterInvoiceResponse, ScanInvoicePagesRequest, ScanInvoicePagesResponse
from app.services.firebase_service import (
    ensure_product_exists,
    get_invoice,
    list_products,
    get_products_by_skus,
    save_invoice_record,
    upsert_order_from_invoice,
)
from app.services.image_service import download_image
from app.services.invoice_parser_service import parse_invoice_texts
from app.services.ocr_service import OcrUnavailableError, extract_text_from_image
from app.services.openai_service import (
    OpenAIConfigurationError,
    extract_invoice_products_from_images_with_ai,
    extract_invoice_products_with_ai,
)


def _normalize_items(items: list[dict]) -> list[dict]:
    return sorted(
        [
            {
                'sku': str(item['sku']).strip().upper(),
                'description': str(item['description']).strip(),
                'qty': int(item['qty']),
                'rate': round(float(item.get('rate', 0)), 2),
                'amount': round(float(item.get('amount', 0)), 2),
                'category': str(item.get('category') or '').strip(),
                'unitsPerCase': max(1, int(item.get('unitsPerCase') or 1)),
                'alternateSkus': sorted(
                    {
                        str(value).strip().upper()
                        for value in item.get('alternateSkus', [])
                        if str(value).strip()
                    }
                ),
            }
            for item in items
        ],
        key=lambda item: item['sku'],
    )


def _apply_catalog_matches(
    items: list[dict],
    products_by_sku: dict[str, dict] | None = None,
    products_by_alternate_sku: dict[str, dict] | None = None,
) -> tuple[list[dict], list[str]]:
    if not items:
        return items, []

    catalog = products_by_sku or get_products_by_skus([item['sku'] for item in items])
    alternate_catalog = products_by_alternate_sku or {}
    matched_skus: list[str] = []
    normalized: list[dict] = []
    for item in items:
        sku = str(item['sku']).strip().upper()
        matched = catalog.get(sku)
        if matched is None:
            for alternate_sku in item.get('alternateSkus', []):
                matched = alternate_catalog.get(str(alternate_sku).strip().upper())
                if matched:
                    break
        if matched:
            preferred_name = str(matched.get('name') or item['description']).strip()
            second_name = str(matched.get('secondName') or '').strip()
            item = {
                **item,
                'sku': sku,
                'description': preferred_name,
                'catalogName': preferred_name,
                'catalogSecondName': second_name,
                'alternateSkus': sorted(
                    {
                        *[str(value).strip().upper() for value in item.get('alternateSkus', []) if str(value).strip()],
                        *[str(value).strip().upper() for value in matched.get('alternateSkus', []) if str(value).strip()],
                    }
                ),
            }
            matched_skus.append(sku)
        normalized.append(item)
    return normalized, matched_skus


def _normalize_match_text(value: str) -> str:
    return ''.join(char.lower() for char in value if char.isalnum())


def _annotate_description_candidates(
    items: list[dict],
    products: list[dict] | None = None,
) -> list[dict]:
    if not items:
        return items

    products = products or list_products()
    known_by_description: list[tuple[str, str, dict]] = []
    for product in products:
        sku = str(product.get('sku') or '').strip().upper()
        names = [
            product.get('name'),
            product.get('secondName'),
            *(product.get('alternateNames') or []),
        ]
        for raw_name in names:
            name = str(raw_name or '').strip()
            if sku and name:
                known_by_description.append(
                    (sku, _normalize_match_text(name), product)
                )

    normalized_items: list[dict] = []
    for item in items:
        if item.get('catalogName'):
            normalized_items.append(item)
            continue

        item_description = _normalize_match_text(str(item.get('description') or ''))
        item_sku = str(item.get('sku') or '').strip().upper()
        if not item_description:
            normalized_items.append(item)
            continue

        best_match: tuple[str, dict] | None = None
        best_score = 0.0
        for sku, description, product in known_by_description:
            if sku == item_sku:
                continue
            score = SequenceMatcher(None, item_description, description).ratio()
            if score > best_score:
                best_score = score
                best_match = (sku, product)

        if best_match is not None and best_score >= 0.92:
            sku, product = best_match
            item = {
                **item,
                'possibleCatalogSku': sku,
                'possibleCatalogName': str(product.get('name') or item['description']).strip(),
                'possibleCatalogScore': round(best_score, 3),
            }
        normalized_items.append(item)
    return normalized_items


def _extract_alternate_skus(description: str, primary_sku: str) -> list[str]:
    candidates = re.findall(r'\b[A-Z][A-Z0-9]{4,}\b', description.upper())
    return sorted(
        {
            candidate
            for candidate in candidates
            if candidate != primary_sku
            and any(char.isalpha() for char in candidate)
            and any(char.isdigit() for char in candidate)
        }
    )


def _split_combined_sku(raw_sku: str) -> tuple[str, list[str]]:
    sku = raw_sku.strip().upper().replace(' ', '')
    match = re.fullmatch(r'(\d{5,})[-/]+([A-Z][A-Z0-9]{4,})', sku)
    if match:
        return match.group(1), [match.group(2)]
    return sku, []


def _dedupe_duplicate_invoice_lines(items: list[dict]) -> list[dict]:
    deduped: list[dict] = []
    seen_indexes: dict[tuple[str, int, float, float], int] = {}

    for item in items:
        key = (
            _normalize_match_text(str(item.get('description') or '')),
            int(item.get('qty') or 0),
            round(float(item.get('rate') or 0), 2),
            round(float(item.get('amount') or 0), 2),
        )
        if not key[0]:
            deduped.append(item)
            continue

        existing_index = seen_indexes.get(key)
        if existing_index is None:
            seen_indexes[key] = len(deduped)
            deduped.append(item)
            continue

        existing = deduped[existing_index]
        duplicate_sku = str(item.get('sku') or '').strip().upper()
        existing_sku = str(existing.get('sku') or '').strip().upper()
        alternate_skus = {
            str(value).strip().upper()
            for value in existing.get('alternateSkus', [])
            if str(value).strip()
        }
        alternate_skus.update(
            str(value).strip().upper()
            for value in item.get('alternateSkus', [])
            if str(value).strip()
        )
        if duplicate_sku and duplicate_sku != existing_sku:
            alternate_skus.add(duplicate_sku)
        existing['alternateSkus'] = sorted(alternate_skus)

    return deduped


def _normalize_ai_items(raw_items: list[dict]) -> list[dict]:
    normalized: list[dict] = []
    for raw in raw_items:
        description = str(raw.get('description') or '').strip()
        sku, sku_alternates = _split_combined_sku(str(raw.get('sku') or ''))
        if not sku or not description:
            continue
        try:
            qty = max(1, int(float(raw.get('qty') or 1)))
        except (TypeError, ValueError):
            qty = 1
        try:
            rate = round(float(raw.get('rate') or 0), 2)
        except (TypeError, ValueError):
            rate = 0.0
        try:
            amount = round(float(raw.get('amount') or 0), 2)
        except (TypeError, ValueError):
            amount = 0.0
        try:
            units_per_case = max(1, int(float(raw.get('unitsPerCase') or 1)))
        except (TypeError, ValueError):
            units_per_case = 1

        normalized.append(
            {
                'sku': sku,
                'description': description,
                'qty': qty,
                'rate': rate,
                'amount': amount,
                'category': str(raw.get('category') or '').strip(),
                'unitsPerCase': units_per_case,
                'alternateSkus': sorted(
                    {
                        *_extract_alternate_skus(description, sku),
                        *sku_alternates,
                        *[
                            str(value).strip().upper()
                            for value in raw.get('alternateSkus', [])
                            if str(value).strip()
                        ],
                    }
                ),
            }
        )
    return normalized


def _merge_ai_parsed(parsed: dict, ai_parsed: dict[str, object]) -> tuple[dict, bool]:
    ai_items = _normalize_ai_items(ai_parsed.get('items', []) if isinstance(ai_parsed.get('items'), list) else [])
    if ai_items:
        parsed['items'] = ai_items
    for key in ['invoiceNumber', 'invoiceDate', 'storeNumber', 'storeName', 'address']:
        value = str(ai_parsed.get(key) or '').strip()
        if value:
            parsed[key] = value
    parsed['aiEnhanced'] = bool(ai_items)
    return parsed, bool(ai_items)


def _preview_new_product_skus(
    items: list[dict],
    products_by_sku: dict[str, dict] | None = None,
) -> list[str]:
    catalog = products_by_sku or get_products_by_skus([item['sku'] for item in items])
    detected_new_skus: list[str] = []
    for item in items:
        sku = str(item['sku']).strip().upper()
        if sku and sku not in catalog:
            detected_new_skus.append(sku)
    return detected_new_skus


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


def _write_scan_debug_log(
    *,
    invoice_number: str | None,
    page_count: int,
    extracted_texts: list[str],
    parsed: dict,
    message: str,
    timings_ms: dict[str, int] | None = None,
) -> None:
    settings = get_settings()
    timestamp = datetime.now().isoformat(timespec='seconds')
    payload = {
        'timestamp': timestamp,
        'invoiceNumberRequested': invoice_number,
        'pageCount': page_count,
        'message': message,
        'timingsMs': timings_ms or {},
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



async def scan_invoice_pages(request: ScanInvoicePagesRequest) -> ScanInvoicePagesResponse:
    started_at = perf_counter()
    image_urls = [page.imageUrl for page in request.pages if page.imageUrl]
    vision_started_at = perf_counter()
    parsed: dict = {}
    vision_error = ''
    try:
        ai_parsed = await extract_invoice_products_from_images_with_ai(
            image_urls,
            request.invoiceNumber,
        )
        parsed, _vision_enhanced = _merge_ai_parsed({}, ai_parsed)
        parsed['visionEnhanced'] = bool(parsed.get('items'))
    except OpenAIConfigurationError:
        parsed['visionEnhanced'] = False
    except Exception as exc:  # noqa: BLE001
        parsed['visionEnhanced'] = False
        vision_error = str(exc)
    vision_ms = round((perf_counter() - vision_started_at) * 1000)

    download_ocr_started_at = perf_counter()
    texts: list[str] = []
    ocr_available = True
    should_run_ocr_fallback = not parsed.get('items')
    if should_run_ocr_fallback:
        try:
            for page in request.pages:
                if not page.imageUrl:
                    texts.append('')
                    continue
                local_path = download_image(page.imageUrl)
                texts.append(extract_text_from_image(local_path))
        except OcrUnavailableError as exc:
            ocr_available = False
            if not parsed.get('items'):
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

    download_ocr_ms = round((perf_counter() - download_ocr_started_at) * 1000)
    parser_ms = 0
    ai_error = ''
    ai_ms = 0
    if should_run_ocr_fallback:
        parser_started_at = perf_counter()
        parsed = parse_invoice_texts(texts, request.invoiceNumber)
        parser_ms = round((perf_counter() - parser_started_at) * 1000)
        ai_started_at = perf_counter()
        try:
            ai_parsed = await extract_invoice_products_with_ai(texts, request.invoiceNumber)
            parsed, _ai_enhanced = _merge_ai_parsed(parsed, ai_parsed)
        except OpenAIConfigurationError:
            parsed['aiEnhanced'] = False
        except Exception as exc:  # noqa: BLE001
            parsed['aiEnhanced'] = False
            ai_error = str(exc)
        ai_ms = round((perf_counter() - ai_started_at) * 1000)
    else:
        parsed['aiEnhanced'] = True

    catalog_started_at = perf_counter()
    products = list_products()
    products_by_sku = {
        str(product.get('sku') or '').strip().upper(): product
        for product in products
        if str(product.get('sku') or '').strip()
    }
    products_by_alternate_sku = {
        str(alternate_sku).strip().upper(): product
        for product in products
        for alternate_sku in product.get('alternateSkus', [])
        if str(alternate_sku).strip()
    }
    parsed_items = _dedupe_duplicate_invoice_lines(parsed.get('items', []))
    matched_items, matched_skus = _apply_catalog_matches(
        parsed_items,
        products_by_sku,
        products_by_alternate_sku,
    )
    matched_items = _annotate_description_candidates(
        matched_items,
        products,
    )
    parsed['items'] = matched_items
    parsed['catalogMatchedSkus'] = sorted(set(matched_skus))
    parsed['newProductsDetected'] = _preview_new_product_skus(
        matched_items,
        products_by_sku,
    )
    parsed['newProductsCreated'] = []
    catalog_ms = round((perf_counter() - catalog_started_at) * 1000)
    total_ms = round((perf_counter() - started_at) * 1000)
    timings_ms = {
        'visionAi': vision_ms,
        'downloadAndOcr': download_ocr_ms,
        'parser': parser_ms,
        'ai': ai_ms,
        'catalogResolution': catalog_ms,
        'total': total_ms,
    }

    item_count = len(parsed.get('items', []))
    store_ref = parsed.get('storeNumber') or parsed.get('address')
    if item_count:
        catalog_note = f' Catalogo aplicado a {len(parsed["catalogMatchedSkus"])} SKU.' if parsed['catalogMatchedSkus'] else ''
        detected_note = f' Posibles productos nuevos: {len(parsed["newProductsDetected"])}.' if parsed['newProductsDetected'] else ''
        if parsed.get('visionEnhanced'):
            ai_note = ' Vision IA aplicada.'
        else:
            ai_note = ' OCR + IA aplicada.' if parsed.get('aiEnhanced') else (' IA no aplicada.' if not ai_error else f' IA no aplicada: {ai_error}')
        message = (
            f'Se detectaron {item_count} lineas y referencia de tienda: '
            f'{"si" if store_ref else "no"}.{catalog_note}{detected_note}{ai_note} Revisa los datos antes de registrar.'
        )
    else:
        message = 'OCR ejecutado, pero no se detectaron lineas confiables.'

    _write_scan_debug_log(
        invoice_number=request.invoiceNumber,
        page_count=len(request.pages),
        extracted_texts=texts,
        parsed=parsed,
        message=message,
        timings_ms=timings_ms,
    )

    return ScanInvoicePagesResponse(
        ocrAvailable=ocr_available,
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
        rate = float(item.get('rate') or 0)
        created = ensure_product_exists(
            item['sku'],
            item['description'],
            alternate_skus=item.get('alternateSkus', []),
            category=str(item.get('category') or ''),
            cost=rate,
            sale_price=round(rate * 1.3, 2) if rate > 0 else 0.0,
            units_per_case=int(item.get('unitsPerCase') or 1),
        )
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
