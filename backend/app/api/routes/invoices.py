from fastapi import APIRouter

from app.models.schemas import RegisterInvoiceRequest, RegisterInvoiceResponse, ScanInvoicePagesRequest, ScanInvoicePagesResponse
from app.services.invoice_service import register_invoice, scan_invoice_pages

router = APIRouter(prefix='/invoices', tags=['invoices'])


@router.post('/scan-pages', response_model=ScanInvoicePagesResponse)
async def scan_invoice_pages_route(request: ScanInvoicePagesRequest) -> ScanInvoicePagesResponse:
    return await scan_invoice_pages(request)


@router.post('/register', response_model=RegisterInvoiceResponse)
def register_invoice_route(request: RegisterInvoiceRequest) -> RegisterInvoiceResponse:
    return register_invoice(request)
