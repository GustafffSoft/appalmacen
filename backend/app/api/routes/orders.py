from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.core.config import get_settings
from app.models.schemas import PalletAiReview, PalletRequest, ProcessOrderRequest, ProcessOrderResponse
from app.services.firebase_service import save_pallet_plan, update_order_status
from app.services.image_service import download_image
from app.services.invoice_identification_service import identify_products_from_invoice
from app.services.openai_service import OpenAIConfigurationError, review_pallet_plan_with_ai
from app.services.pallet_service import run_palletizing

router = APIRouter(prefix="/orders", tags=["orders"])

MIN_PALLET_HEIGHT_IN = 83.0
MAX_PALLET_HEIGHT_IN = 86.0


def _normalize_pallet(request_pallet: PalletRequest | None, settings) -> PalletRequest:
    pallet = request_pallet or PalletRequest(
        lengthCm=settings.pallet_length_cm_default,
        widthCm=settings.pallet_width_cm_default,
        maxHeightCm=settings.pallet_max_height_cm_default,
        maxWeightKg=settings.pallet_max_weight_kg_default,
    )

    bounded_height = min(max(pallet.maxHeightCm, MIN_PALLET_HEIGHT_IN), MAX_PALLET_HEIGHT_IN)
    return PalletRequest(
        lengthCm=pallet.lengthCm,
        widthCm=pallet.widthCm,
        maxHeightCm=round(bounded_height, 2),
        maxWeightKg=pallet.maxWeightKg,
    )


async def _build_ai_review(boxes, pallet_views, overall_stats, pallet, packing_log) -> PalletAiReview | None:
    try:
        review_payload, model = await review_pallet_plan_with_ai(
            pallet=pallet,
            boxes=boxes,
            pallets=pallet_views,
            stats=overall_stats,
            packing_log=packing_log,
        )
    except OpenAIConfigurationError:
        return None
    except Exception as exc:  # noqa: BLE001
        return PalletAiReview(
            riskLevel="unknown",
            finalAnswer=f"No se pudo generar la respuesta final IA del pallet. Usa el layout visual calculado por el sistema. Detalle tecnico: {exc}",
        )

    review_payload["model"] = model
    return PalletAiReview(**review_payload)


@router.post("/{orderId}/process", response_model=ProcessOrderResponse)
async def process_order(orderId: str, request: ProcessOrderRequest) -> ProcessOrderResponse:
    settings = get_settings()

    pallet = _normalize_pallet(request.pallet, settings)
    allow_overhang_cm = 0.0

    try:
        update_order_status(orderId, "processing")

        local_image_path = ""
        if request.imageUrl:
            local_image_path = str(download_image(request.imageUrl))

        identification_mode, detected_items = identify_products_from_invoice(orderId, local_image_path)

        if not detected_items:
            raise ValueError("No items identified. Add products/qty to the order before processing.")

        boxes, pallet_views, overall_stats, packing_log = run_palletizing(detected_items, pallet, allow_overhang_cm)

        if not pallet_views:
            raise ValueError("No boxes could be packed into any pallet.")

        ai_review = await _build_ai_review(
            boxes,
            pallet_views,
            overall_stats,
            pallet,
            packing_log,
        )

        first_pallet = pallet_views[0]

        response = ProcessOrderResponse(
            orderId=orderId,
            status="processed",
            identificationMode=identification_mode,
            allowOverhangCm=allow_overhang_cm,
            pallet=pallet,
            boxes=boxes,
            layout=first_pallet.layout,
            stats=overall_stats,
            palletCount=len(pallet_views),
            pallets=pallet_views,
            packingLog=packing_log,
            aiReview=ai_review,
        )

        payload = response.model_dump(mode="json")
        save_pallet_plan(orderId, payload)

        extra_payload = {
            "allowOverhangCm": allow_overhang_cm,
            "identificationMode": identification_mode,
            "palletCount": len(pallet_views),
        }
        if request.imageUrl:
            extra_payload["imageUrl"] = request.imageUrl

        update_order_status(orderId, "processed", extra=extra_payload)
        return response
    except Exception as exc:  # noqa: BLE001
        try:
            update_order_status(orderId, "error", extra={"errorMessage": str(exc)})
        except Exception:
            pass
        raise HTTPException(status_code=500, detail=f"Order processing failed: {exc}") from exc

