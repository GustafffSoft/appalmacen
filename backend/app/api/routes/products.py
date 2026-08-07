from fastapi import APIRouter, Depends, HTTPException, status

from app.api.dependencies.auth import (
    AuthenticatedUser,
    require_active_user,
    require_roles,
)
from app.models.schemas import (
    MergeProductsRequest,
    MergeProductsResponse,
    Product,
    ProductResearchRequest,
    ProductResearchResponse,
    ScanProductCatalogRequest,
    ScanProductCatalogResponse,
    SeedProductsResponse,
)
from app.services.firebase_service import (
    ProductMergeError,
    get_product_by_sku,
    list_products,
    merge_products,
    update_product_research,
    upsert_products,
)
from app.services.openai_service import research_product_with_web
from app.services.product_catalog_scan_service import scan_product_catalog
from app.services.product_service import SEED_PRODUCTS

router = APIRouter(
    prefix="/products",
    tags=["products"],
    dependencies=[Depends(require_active_user)],
)


@router.post(
    "/scan-catalog",
    response_model=ScanProductCatalogResponse,
    dependencies=[Depends(require_roles("admin", "warehouse"))],
)
async def scan_product_catalog_route(
    request: ScanProductCatalogRequest,
) -> ScanProductCatalogResponse:
    return await scan_product_catalog(request)


@router.get("", response_model=list[Product])
def get_products() -> list[Product]:
    return [Product(**item) for item in list_products()]


@router.post(
    "/seed",
    response_model=SeedProductsResponse,
    dependencies=[Depends(require_roles("admin"))],
)
def seed_products() -> SeedProductsResponse:
    inserted = upsert_products(SEED_PRODUCTS)
    return SeedProductsResponse(
        inserted=inserted, skus=[str(p["sku"]) for p in SEED_PRODUCTS]
    )


@router.post("/merge", response_model=MergeProductsResponse)
def merge_products_route(
    request: MergeProductsRequest,
    user: AuthenticatedUser = Depends(require_roles("admin")),
) -> MergeProductsResponse:
    try:
        result = merge_products(
            request.sourceSku,
            request.targetSku,
            actor_uid=user.uid,
            actor_email=user.email,
        )
    except ProductMergeError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(error),
        ) from error
    return MergeProductsResponse(**result)


@router.post(
    "/{sku}/research",
    response_model=ProductResearchResponse,
    dependencies=[Depends(require_roles("admin", "warehouse"))],
)
async def research_product(
    sku: str, request: ProductResearchRequest
) -> ProductResearchResponse:
    existing = get_product_by_sku(sku.upper()) or {}
    payload, model = await research_product_with_web(
        ProductResearchRequest(
            sku=sku.upper(),
            name=request.name,
            secondName=request.secondName,
            category=request.category,
            alternateSkus=request.alternateSkus,
            previousResearch={
                "confidence": existing.get("researchConfidence"),
                "needsManualReview": existing.get("researchNeedsManualReview"),
                "notes": existing.get("researchNotes"),
                "sources": existing.get("researchSources") or [],
                "reviewedSourceUrls": existing.get("researchReviewedSourceUrls") or [],
                "rejectedSourceUrls": existing.get("researchRejectedSourceUrls") or [],
                "hasCaseDimensions": existing.get("researchHasCaseDimensions"),
                "hasCaseWeight": existing.get("researchHasCaseWeight"),
                "hasCaseImage": existing.get("researchHasCaseImage"),
            },
        )
    )
    payload["model"] = model
    response = ProductResearchResponse(**payload)
    update_product_research(sku, response.model_dump(mode="json"))
    return response
