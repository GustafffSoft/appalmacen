from __future__ import annotations

import httpx
from fastapi import APIRouter, Depends, HTTPException

from app.api.dependencies.auth import require_roles
from app.models.schemas import GenerateSalesMessageRequest, GenerateSalesMessageResponse
from app.services.openai_service import OpenAIConfigurationError, generate_sales_message

router = APIRouter(
    prefix="/ai",
    tags=["ai"],
    dependencies=[Depends(require_roles("admin", "sales"))],
)


@router.post("/sales-message", response_model=GenerateSalesMessageResponse)
async def sales_message(
    request: GenerateSalesMessageRequest,
) -> GenerateSalesMessageResponse:
    try:
        message, model = await generate_sales_message(request)
        return GenerateSalesMessageResponse(message=message, model=model)
    except OpenAIConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except httpx.HTTPStatusError as exc:
        detail = exc.response.text
        raise HTTPException(
            status_code=502, detail=f"OpenAI request failed: {detail}"
        ) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=500, detail=f"AI sales message failed: {exc}"
        ) from exc
