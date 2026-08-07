from __future__ import annotations

import httpx
import json

from app.core.config import get_settings
from app.models.schemas import (
    BoxPlan,
    GenerateSalesMessageRequest,
    PalletPlanView,
    PalletRequest,
    ProductResearchRequest,
    StatsResponse,
)


class OpenAIConfigurationError(RuntimeError):
    pass


_CATALOG_RESPONSE_FORMAT = {
    "type": "json_schema",
    "name": "catalog_products",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "products": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "sku": {"type": "string"},
                        "description": {"type": "string"},
                        "secondName": {"type": "string"},
                        "category": {"type": "string"},
                        "brand": {"type": "string"},
                        "manufacturer": {"type": "string"},
                        "packDescription": {"type": "string"},
                        "unitsPerCase": {"type": "integer"},
                        "alternateSkus": {
                            "type": "array",
                            "items": {"type": "string"},
                        },
                        "barcode": {"type": "string"},
                        "color": {"type": "string"},
                        "material": {"type": "string"},
                        "size": {"type": "string"},
                    },
                    "required": [
                        "sku",
                        "description",
                        "secondName",
                        "category",
                        "brand",
                        "manufacturer",
                        "packDescription",
                        "unitsPerCase",
                        "alternateSkus",
                        "barcode",
                        "color",
                        "material",
                        "size",
                    ],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["products"],
        "additionalProperties": False,
    },
}

_INVOICE_RESPONSE_FORMAT = {
    "type": "json_schema",
    "name": "invoice_products",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "invoiceNumber": {"type": "string"},
            "invoiceDate": {"type": "string"},
            "storeNumber": {"type": "string"},
            "storeName": {"type": "string"},
            "address": {"type": "string"},
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "sku": {"type": "string"},
                        "description": {"type": "string"},
                        "qty": {"type": "integer"},
                        "rate": {"type": "number"},
                        "amount": {"type": "number"},
                        "category": {"type": "string"},
                        "unitsPerCase": {"type": "integer"},
                        "alternateSkus": {
                            "type": "array",
                            "items": {"type": "string"},
                        },
                    },
                    "required": [
                        "sku",
                        "description",
                        "qty",
                        "rate",
                        "amount",
                        "category",
                        "unitsPerCase",
                        "alternateSkus",
                    ],
                    "additionalProperties": False,
                },
            },
        },
        "required": [
            "invoiceNumber",
            "invoiceDate",
            "storeNumber",
            "storeName",
            "address",
            "items",
        ],
        "additionalProperties": False,
    },
}


def _build_prompt(request: GenerateSalesMessageRequest) -> str:
    product_lines = []
    for product in request.products:
        product_lines.append(
            (
                f"- SKU: {product.sku}; nombre: {product.name}; "
                f"categoria: {product.category or 'sin categoria'}; "
                f"precio venta: {product.salePrice:.2f}; margen: {product.marginPct:.1f}%"
            )
        )

    likely_products = (
        ", ".join(request.likelyProducts)
        if request.likelyProducts
        else "No especificado"
    )
    return (
        f"Cliente: {request.prospectName}\n"
        f"Tipo de negocio: {request.prospectType or 'No especificado'}\n"
        f"Zona: {request.area or 'No especificado'}\n"
        f"Notas del cliente: {request.notes or 'No especificado'}\n"
        f"Productos probables del cliente: {likely_products}\n"
        f"Canal: {request.channel}\n"
        f"Idioma: {request.language}\n"
        "Productos seleccionados:\n" + "\n".join(product_lines)
    )


def _extract_output_text(payload: dict[str, object]) -> str:
    output_text = payload.get("output_text")
    if isinstance(output_text, str) and output_text.strip():
        return output_text.strip()

    chunks: list[str] = []
    for item in (
        payload.get("output", []) if isinstance(payload.get("output"), list) else []
    ):
        if not isinstance(item, dict):
            continue
        for content in (
            item.get("content", []) if isinstance(item.get("content"), list) else []
        ):
            if not isinstance(content, dict):
                continue
            text = content.get("text")
            if isinstance(text, str):
                chunks.append(text)
    return "\n".join(chunks).strip()


async def generate_sales_message(
    request: GenerateSalesMessageRequest,
) -> tuple[str, str]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise OpenAIConfigurationError(
            "OPENAI_API_KEY is not configured in backend/.env"
        )

    instructions = (
        "You are a practical B2B sales assistant for a restaurant supply warehouse. "
        "The sender is Gustavo from AppAlmacen, a local restaurant supplies warehouse. "
        "Write one concise, human message the warehouse owner can send manually. "
        "Do not sound like spam. Mention only the selected products. "
        "Use a friendly direct tone, no emojis, no markdown, no subject line. "
        "Never use placeholders like [Your Name], [Warehouse], [Company], or similar. "
        "If you mention the sender, use exactly Gustavo. If you mention the business, use exactly AppAlmacen. "
        "For Spanish messages, prefer opening with: Hola, soy Gustavo de AppAlmacen. "
        "For English messages, prefer opening with: Hi, this is Gustavo from AppAlmacen. "
        "If language is es, write natural Spanish for a Latin business owner in the US. "
        "If language is en, write natural English. "
        "For WhatsApp or SMS, keep it short. For call, write a short call script."
    )

    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "instructions": instructions,
                "input": _build_prompt(request),
            },
        )

    response.raise_for_status()
    message = _extract_output_text(response.json())
    if not message:
        raise RuntimeError("OpenAI returned an empty message")
    return message, settings.openai_model


def _build_pallet_review_payload(
    *,
    pallet: PalletRequest,
    boxes: list[BoxPlan],
    pallets: list[PalletPlanView],
    stats: StatsResponse,
    packing_log: list[str],
) -> dict[str, object]:
    return {
        "pallet": pallet.model_dump(mode="json"),
        "overallStats": stats.model_dump(mode="json"),
        "boxes": [box.model_dump(mode="json") for box in boxes],
        "pallets": [
            {
                "palletNo": pallet_view.palletNo,
                "stats": pallet_view.stats.model_dump(mode="json"),
                "layers": [
                    layer.model_dump(mode="json")
                    for layer in (
                        pallet_view.packingSummary.layers
                        if pallet_view.packingSummary
                        else []
                    )
                ],
                "topLayoutSample": [
                    item.model_dump(mode="json") for item in pallet_view.layout[:30]
                ],
            }
            for pallet_view in pallets
        ],
        "packingLogSample": packing_log[:30],
    }


async def review_pallet_plan_with_ai(
    *,
    pallet: PalletRequest,
    boxes: list[BoxPlan],
    pallets: list[PalletPlanView],
    stats: StatsResponse,
    packing_log: list[str],
) -> tuple[dict[str, object], str]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise OpenAIConfigurationError(
            "OPENAI_API_KEY is not configured in backend/.env"
        )

    instructions = (
        "You are a warehouse palletizing operator for restaurant supply products. "
        "Convert a deterministic pallet plan into one final instruction for the person building the pallet. "
        "The deterministic algorithm is the source of truth for coordinates, pallet count, dimensions, layers, and weight. "
        "Do not give optional recommendations. Do not say maybe, could, consider, or review. "
        "Do not invent new coordinates or a different layout. "
        "State the best final way to build the pallet plan using the provided layout and layer summaries. "
        "Mention the number of pallets, which boxes go low/heavy, how to build layers, and any mandatory caution only if the plan has unpacked boxes or high risk. "
        "Return only valid JSON, no markdown. Use this exact shape: "
        '{"riskLevel":"low|medium|high","finalAnswer":""}. '
        "Write natural Spanish for a warehouse operator in the US. "
        "finalAnswer must be one concise operational answer, not a list of suggestions."
    )
    input_payload = _build_pallet_review_payload(
        pallet=pallet,
        boxes=boxes,
        pallets=pallets,
        stats=stats,
        packing_log=packing_log,
    )

    async with httpx.AsyncClient(timeout=35) as client:
        response = await client.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "instructions": instructions,
                "input": json.dumps(input_payload, ensure_ascii=True)[:28000],
            },
        )

    response.raise_for_status()
    payload = _extract_json_object(_extract_output_text(response.json()))
    return payload, settings.openai_model


async def research_product_with_web(
    request: ProductResearchRequest,
) -> tuple[dict[str, object], str]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise OpenAIConfigurationError(
            "OPENAI_API_KEY is not configured in backend/.env"
        )

    query_payload = {
        "sku": request.sku,
        "name": request.name,
        "secondName": request.secondName or "",
        "category": request.category or "",
        "alternateSkus": request.alternateSkus,
        "previousResearch": request.previousResearch or {},
    }
    instructions = (
        "You are a product data researcher for a restaurant supply warehouse. "
        "Use web search to find the most reliable product/case information for the given SKU and name. "
        "Prefer manufacturer pages, distributor product pages, and official catalog/spec pages. "
        "Use previousResearch as memory. If prior sources did not provide case/carton details, search beyond those domains and try different queries. "
        "You may reuse a prior source only if it contains new useful case/carton evidence or confirms a field. "
        "Treat rejectedSourceUrls as already reviewed and not useful for case/carton data unless there is no better source; do not rely on them for high confidence. "
        "Search specifically for master case, case, carton, outer carton, shipping carton, or shipping dimensions. "
        "Search with combinations such as SKU + case dimensions, SKU + carton dimensions, SKU + case weight, "
        "SKU + shipping dimensions, and alternate SKU + master carton. "
        "Find case dimensions, case weight, units per case, and what the product is used for. "
        "Only put values in lengthCm, widthCm, and heightCm when they are clearly case/carton/shipping dimensions, not individual item dimensions. "
        "Only put a value in weightKg when it is clearly case/carton/shipping weight, not individual item weight. "
        "If dimensions are in inches, convert to centimeters. If weight is in pounds, convert to kilograms. "
        "Do not guess. If case/carton dimensions are not found from reliable sources, return 0 for lengthCm, widthCm, and heightCm. "
        "If case/carton weight is not found from reliable sources, return 0 for weightKg. "
        "Set hasCaseDimensions true only when the dimensions are explicitly for the case/carton/shipping carton. "
        "Set hasCaseWeight true only when the weight is explicitly for the case/carton/shipping carton. "
        "Also find a direct or page image URL for the product itself and, separately, an image URL for the case/carton if available. "
        "Set hasProductImage true only when productImageUrl clearly shows the product. "
        "Set hasCaseImage true only when caseImageUrl clearly shows the outer case/carton/master case, not just the product. "
        "If you cannot verify a case/carton image, leave caseImageUrl empty and hasCaseImage false. "
        "Mark needsManualReview true unless both case dimensions and case weight are found with high confidence. "
        "Return only valid JSON, no markdown. Use this exact shape: "
        '{"sku":"","name":"","lengthCm":0,"widthCm":0,"heightCm":0,'
        '"weightKg":0,"unitsPerCase":1,"useCase":"","confidence":"low|medium|high",'
        '"needsManualReview":true,"notes":"","hasCaseDimensions":false,"hasCaseWeight":false,'
        '"productImageUrl":"","caseImageUrl":"","hasProductImage":false,"hasCaseImage":false,'
        '"sources":[{"title":"","url":""}],"reviewedSourceUrls":[""],"rejectedSourceUrls":[""]}. '
        "In notes, say clearly whether found dimensions/images were case/carton or only individual item information. "
        "Put every source URL you reviewed in reviewedSourceUrls. Put URLs that only had individual item data or no useful case/carton data in rejectedSourceUrls. "
        "Keep sources to the best 1 to 4 URLs actually used."
    )

    async with httpx.AsyncClient(timeout=55) as client:
        response = await client.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "tools": [{"type": "web_search"}],
                "tool_choice": "auto",
                "instructions": instructions,
                "input": json.dumps(query_payload, ensure_ascii=True),
            },
        )

    response.raise_for_status()
    payload = _extract_json_object(_extract_output_text(response.json()))
    payload.setdefault("sku", request.sku)
    payload.setdefault("name", request.name)
    return payload, settings.openai_model


def _extract_json_object(text: str) -> dict[str, object]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()

    try:
        payload = json.loads(cleaned)
        return payload if isinstance(payload, dict) else {}
    except json.JSONDecodeError:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start == -1 or end == -1 or end <= start:
            return {}
        try:
            payload = json.loads(cleaned[start : end + 1])
            return payload if isinstance(payload, dict) else {}
        except json.JSONDecodeError:
            return {}


async def extract_invoice_products_with_ai(
    texts: list[str],
    requested_invoice_number: str | None = None,
) -> dict[str, object]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise OpenAIConfigurationError(
            "OPENAI_API_KEY is not configured in backend/.env"
        )

    ocr_text = "\n\n--- PAGE ---\n\n".join(texts)
    instructions = (
        "You extract structured data from OCR text for restaurant supply invoices. "
        "Return only valid JSON, no markdown. "
        "Use this exact shape: "
        '{"invoiceNumber":"","invoiceDate":"","storeNumber":"","storeName":"",'
        '"address":"","items":[{"sku":"","description":"","qty":1,'
        '"rate":0,"amount":0,"category":"","unitsPerCase":1,"alternateSkus":[]}]}. '
        "Rules: include only real product lines from the invoice, not totals, taxes, headers, addresses, or notes. "
        "SKU should be the item code from the SKU/item column if visible. "
        "If the description contains another product code, keep it in alternateSkus instead of making a second line. "
        "qty must be at least 1. "
        "rate and amount should be numeric if visible, otherwise 0. "
        "category should be a short restaurant-supply category such as Vasos, Platos, Bolsas, Contenedores, Cubiertos, Servilletas, Limpieza, Papel, Otro. "
        "unitsPerCase should be inferred only when obvious from pack/case wording, otherwise 1. "
        "If uncertain about a field, leave it empty or 0 rather than inventing."
    )
    input_text = (
        f"Requested invoice number: {requested_invoice_number or ''}\n\n"
        f"OCR text:\n{ocr_text[:24000]}"
    )

    async with httpx.AsyncClient(timeout=45) as client:
        response = await client.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "instructions": instructions,
                "input": input_text,
                "text": {"format": _INVOICE_RESPONSE_FORMAT},
            },
        )

    response.raise_for_status()
    raw = _extract_output_text(response.json())
    return _extract_json_object(raw)


async def extract_invoice_products_from_images_with_ai(
    image_urls: list[str],
    requested_invoice_number: str | None = None,
) -> dict[str, object]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise OpenAIConfigurationError(
            "OPENAI_API_KEY is not configured in backend/.env"
        )

    instructions = (
        "You extract structured data from invoice images for a restaurant supply warehouse. "
        "Return only valid JSON, no markdown. "
        "Use this exact shape: "
        '{"invoiceNumber":"","invoiceDate":"","storeNumber":"","storeName":"",'
        '"address":"","items":[{"sku":"","description":"","qty":1,'
        '"rate":0,"amount":0,"category":"","unitsPerCase":1,"alternateSkus":[]}]}. '
        "Read the table visually from the invoice image, preserving the real SKU from the SKU/item column when visible. "
        "If the description contains another product code, keep it in alternateSkus instead of making a second line. "
        "When several images are pages of the same invoice, read all pages but do not duplicate a line that appears again from page overlap. "
        "Include only real product lines, not totals, taxes, headers, addresses, or notes. "
        "qty must be at least 1. rate and amount should be numeric if visible, otherwise 0. "
        "category should be a short restaurant-supply category such as Vasos, Platos, Bolsas, "
        "Contenedores, Cubiertos, Servilletas, Limpieza, Papel, Otro. "
        "unitsPerCase should be inferred only when obvious from pack/case wording, otherwise 1. "
        "If uncertain about a field, leave it empty or 0 rather than inventing."
    )

    content: list[dict[str, object]] = [
        {
            "type": "input_text",
            "text": f'Requested invoice number: {requested_invoice_number or ""}',
        }
    ]
    for image_url in image_urls:
        content.append(
            {
                "type": "input_image",
                "image_url": image_url,
                "detail": "high",
            }
        )

    async with httpx.AsyncClient(timeout=90) as client:
        response = await client.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "instructions": instructions,
                "input": [
                    {
                        "role": "user",
                        "content": content,
                    }
                ],
                "text": {"format": _INVOICE_RESPONSE_FORMAT},
            },
        )

    response.raise_for_status()
    raw = _extract_output_text(response.json())
    return _extract_json_object(raw)


async def extract_catalog_products_from_images_with_ai(
    image_urls: list[str],
    *,
    retry_for_empty: bool = False,
) -> dict[str, object]:
    settings = get_settings()
    if not settings.openai_api_key:
        raise OpenAIConfigurationError(
            "OPENAI_API_KEY is not configured in backend/.env"
        )

    instructions = (
        "You extract product catalog data from images for a restaurant supply warehouse. "
        "Images may contain invoices, packing lists, product labels, cartons, catalog pages, or tables. "
        "Return only valid JSON, no markdown. Use this exact shape: "
        '{"products":[{"sku":"","description":"","secondName":"",'
        '"category":"Otro","brand":"","manufacturer":"","packDescription":"",'
        '"unitsPerCase":1,"alternateSkus":[],"barcode":"","color":"",'
        '"material":"","size":""}]}. '
        "Extract only real products. Ignore invoice number, dates, customer, supplier, address, quantities ordered, "
        "prices, rates, amounts, taxes, totals, balances, and payment information. "
        "Preserve the exact SKU/item code from its column or label. Do not invent an SKU. "
        "description must be the product description only. Keep additional codes in alternateSkus. "
        "Infer category and unitsPerCase only when supported by visible text. "
        "Deduplicate repeated products across images by primary SKU. "
        "If a field is uncertain, leave it empty rather than inventing it."
    )
    content: list[dict[str, object]] = [
        {
            "type": "input_text",
            "text": (
                "A previous analysis found no products. Inspect every visible table "
                "row carefully and return all rows that have both an item code and "
                "a product description. Do not invent unreadable values."
                if retry_for_empty
                else "Extract product catalog data only. Do not extract prices or invoice data."
            ),
        }
    ]
    for image_url in image_urls:
        content.append(
            {"type": "input_image", "image_url": image_url, "detail": "high"}
        )

    async with httpx.AsyncClient(timeout=90) as client:
        response = await client.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.openai_model,
                "instructions": instructions,
                "input": [{"role": "user", "content": content}],
                "text": {"format": _CATALOG_RESPONSE_FORMAT},
            },
        )

    response.raise_for_status()
    raw = _extract_output_text(response.json())
    return _extract_json_object(raw)
