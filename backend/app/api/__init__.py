from fastapi import APIRouter

from app.api.routes.ai import router as ai_router
from app.api.routes.health import router as health_router
from app.api.routes.invoices import router as invoices_router
from app.api.routes.orders import router as orders_router
from app.api.routes.products import router as products_router

api_router = APIRouter()
api_router.include_router(health_router)
api_router.include_router(ai_router)
api_router.include_router(products_router)
api_router.include_router(invoices_router)
api_router.include_router(orders_router)
