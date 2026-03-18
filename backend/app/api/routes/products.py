from fastapi import APIRouter

from app.models.schemas import Product, SeedProductsResponse
from app.services.firebase_service import list_products, upsert_products
from app.services.product_service import SEED_PRODUCTS

router = APIRouter(prefix="/products", tags=["products"])


@router.get("", response_model=list[Product])
def get_products() -> list[Product]:
    return [Product(**item) for item in list_products()]


@router.post("/seed", response_model=SeedProductsResponse)
def seed_products() -> SeedProductsResponse:
    inserted = upsert_products(SEED_PRODUCTS)
    return SeedProductsResponse(inserted=inserted, skus=[str(p["sku"]) for p in SEED_PRODUCTS])