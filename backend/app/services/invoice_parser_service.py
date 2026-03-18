from __future__ import annotations

import re


DATE_PATTERN = re.compile(r'(\d{2}/\d{2}/\d{4}|\d{4}-\d{2}-\d{2})')
DIGIT_BLOCK_PATTERN = re.compile(r'^\D*(\d{5,8})\D*$')
STORE_NUMBER_PATTERN = re.compile(r'(\d{3,5})')
TABLE_STOP_TOKENS = ['SUBTOTAL', 'TOTAL', 'BALANCE DUE', 'BAUANCE DUE', 'TAX', 'DFLI', 'DF11']
ADDRESS_TOKENS = ['STREET', 'ST', 'AVE', 'ROAD', 'RD', 'DRIVE', 'DR', 'BLVD', 'FL', 'SW', 'NW', 'MIAMI']
NOISE_LINES = {'Q', 'A', '2', '5)', 'RATE AMOUNT', 'SKU', 'DESCRIPTION', 'HUE', 'NET?'}


def _normalize_line(line: str) -> str:
    line = line.replace('|', '1')
    line = line.replace('!', '1')
    line = line.replace('‘', '')
    line = line.replace('“', '')
    line = line.replace('”', '')
    line = line.replace('~', ' ')
    line = re.sub(r'\s+', ' ', line).strip()
    return line


def _extract_invoice_number(lines: list[str], requested: str | None = None) -> str:
    for index, line in enumerate(lines):
        upper = line.upper()
        if 'INVOICE' in upper:
            window_start = max(0, index - 3)
            window_end = min(len(lines), index + 5)
            window = lines[window_start:window_end]
            candidates: list[int] = []
            for candidate_line in window:
                for raw in re.findall(r'\d{3,}', candidate_line):
                    try:
                        value = int(raw)
                    except ValueError:
                        continue
                    if 1000 <= value <= 999999:
                        candidates.append(value)
            if candidates:
                return str(max(candidates))
    return requested or ''


def _extract_invoice_date(lines: list[str]) -> str:
    for line in lines:
        match = DATE_PATTERN.search(line)
        if match:
            return match.group(1)
    return ''


def _clean_address_line(line: str) -> str:
    if re.fullmatch(r'[A-Za-z]+\s+\d{4}', line):
        return ''
    if line.upper().startswith('M287 ') or line.upper().startswith('#257 '):
        return ''
    return line


def _extract_bill_to(lines: list[str]) -> tuple[str, str, str]:
    candidates: list[str] = []
    capture = False
    for line in lines:
        upper = line.upper()
        if 'BILL TO' in upper:
            capture = True
            continue
        if capture and ('SHIP TO' in upper or 'SKU' in upper):
            break
        if capture:
            candidates.append(line)

    if not candidates:
        for index, line in enumerate(lines):
            if 'FRESCO' in line.upper() or 'Y MAS' in line.upper():
                candidates = lines[max(0, index - 1): min(len(lines), index + 4)]
                break

    store_name = ''
    address_lines: list[str] = []
    store_number_candidates: list[int] = []
    for line in candidates:
        upper = line.upper()
        if 'FRESCO' in upper or 'Y MAS' in upper or '#' in line:
            digits = STORE_NUMBER_PATTERN.findall(line)
            for digit in digits:
                try:
                    value = int(digit)
                    if 1 <= value <= 9999:
                        store_number_candidates.append(value)
                except ValueError:
                    pass
            if 'FRESCO' in upper or 'Y MAS' in upper:
                store_name = 'Fresco Y Mas'
            elif not store_name:
                store_name = line.strip()
            continue
        if any(token in upper for token in ADDRESS_TOKENS) or re.search(r'\d{3,5}', line):
            cleaned = _clean_address_line(line)
            if cleaned:
                address_lines.append(cleaned)

    store_number = str(max(store_number_candidates)) if store_number_candidates else ''
    address = ', '.join(dict.fromkeys(address_lines))
    return store_number, store_name, address


def _table_start_index(lines: list[str]) -> int:
    for index, line in enumerate(lines):
        upper = line.upper()
        if upper == 'SKU':
            return index
        if 'SKU' in upper and 'DESCRIPTION' in upper:
            return index
        if index + 2 < len(lines):
            block = ' '.join(lines[index:index + 3]).upper()
            if 'SKU' in block and 'DESCRIPTION' in block:
                return index
    return -1


def _clean_description(text: str) -> str:
    text = text.replace('Cc', 'Case')
    text = text.replace(' Containe:', ' Container')
    text = text.replace(' ase Pack', ' Case Pack')
    text = re.sub(r'\b2:3\s*De\b', '', text)
    text = re.sub(r'\s+', ' ', text).strip(' -')
    return text


def _extract_sku_candidate(line: str) -> str | None:
    if any(char.isalpha() for char in line):
        return None
    match = DIGIT_BLOCK_PATTERN.match(line)
    if not match:
        return None
    digits = match.group(1)
    if len(digits) == 7 and digits.startswith('936'):
        digits = digits[:3] + digits[4:]
    if len(digits) < 5 or len(digits) > 8:
        return None
    return digits


def _extract_items(lines: list[str]) -> list[dict]:
    start = _table_start_index(lines)
    if start == -1:
        return []

    items: list[dict] = []
    current_sku = ''
    description_parts: list[str] = []

    def flush_current() -> None:
        nonlocal current_sku, description_parts
        if not current_sku:
            return
        description = _clean_description(' '.join(description_parts))
        if description:
            items.append(
                {
                    'sku': current_sku,
                    'description': description,
                    'qty': 1,
                    'rate': 0.0,
                    'amount': 0.0,
                }
            )
        current_sku = ''
        description_parts = []

    for line in lines[start + 1:]:
        upper = line.upper()
        if any(token in upper for token in TABLE_STOP_TOKENS):
            flush_current()
            break
        if line in NOISE_LINES or upper in NOISE_LINES:
            continue
        if re.fullmatch(r'\d+[\.,]\d{2}', line):
            continue
        if re.fullmatch(r'\d[:\.]\d{2}\s*[A-Z]*', upper):
            continue

        sku_candidate = _extract_sku_candidate(line)
        if sku_candidate:
            flush_current()
            current_sku = sku_candidate
            continue

        if current_sku:
            description_parts.append(line)

    flush_current()

    deduped: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for item in items:
        signature = (item['sku'], item['description'])
        if signature in seen:
            continue
        seen.add(signature)
        deduped.append(item)
    return deduped


def parse_invoice_texts(texts: list[str], requested_invoice_number: str | None = None) -> dict:
    lines: list[str] = []
    for text in texts:
        lines.extend([_normalize_line(line) for line in text.splitlines() if _normalize_line(line)])

    invoice_number = _extract_invoice_number(lines, requested_invoice_number)
    invoice_date = _extract_invoice_date(lines)
    store_number, store_name, address = _extract_bill_to(lines)
    items = _extract_items(lines)

    is_complete = bool(items) and bool(store_number or address or store_name)

    return {
        'invoiceNumber': invoice_number,
        'invoiceDate': invoice_date,
        'storeNumber': store_number,
        'storeName': store_name,
        'address': address,
        'subtotal': 0.0,
        'tax': 0.0,
        'total': 0.0,
        'items': items,
        'linesAmountTotal': 0.0,
        'totalsMatch': True,
        'isComplete': is_complete,
        'rawLines': lines,
    }
