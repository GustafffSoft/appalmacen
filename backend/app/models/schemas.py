from pydantic import BaseModel, Field


class PalletRequest(BaseModel):
    lengthCm: float = Field(..., gt=0)
    widthCm: float = Field(..., gt=0)
    maxHeightCm: float = Field(..., gt=0)
    maxWeightKg: float = Field(..., gt=0)


class ProcessOrderRequest(BaseModel):
    imageUrl: str | None = None
    allowOverhangCm: float | None = Field(default=None, ge=0)
    pallet: PalletRequest | None = None


class OrderItem(BaseModel):
    sku: str
    qty: int = Field(..., ge=1)


class Product(BaseModel):
    sku: str
    name: str
    secondName: str | None = None
    lengthCm: float
    widthCm: float
    heightCm: float
    weightKg: float
    imageRef: str | None = None


class DetectedItem(BaseModel):
    boxId: str
    sku: str
    name: str
    lengthCm: float
    widthCm: float
    heightCm: float
    weightKg: float
    qty: int = Field(default=1, ge=1)


class LayoutItem(BaseModel):
    boxId: str
    x: float
    y: float
    z: float
    rotation: int
    layer: int
    lengthCm: float
    widthCm: float
    heightCm: float
    weightKg: float
    sku: str | None = None
    name: str | None = None


class StatsResponse(BaseModel):
    totalWeightKg: float
    usedVolumeCm3: float
    utilizationPct: float
    unpackedCount: int


class BoxPlan(BaseModel):
    boxId: str
    sku: str
    name: str
    lengthCm: float
    widthCm: float
    heightCm: float
    weightKg: float
    qty: int


class LayerSummary(BaseModel):
    layer: int
    zStart: float
    maxHeight: float
    boxCount: int
    baseAreaUsed: float
    baseCoveragePct: float
    totalWeightKg: float
    boxNames: list[str]


class PackingSummary(BaseModel):
    rules: list[str]
    layers: list[LayerSummary]
    notes: list[str]


class PalletPlanView(BaseModel):
    palletNo: int
    layout: list[LayoutItem]
    stats: StatsResponse
    packingSummary: PackingSummary | None = None


class InvoiceLineItem(BaseModel):
    sku: str
    description: str
    qty: int = Field(..., ge=1)
    rate: float = Field(default=0, ge=0)
    amount: float = Field(default=0, ge=0)


class InvoicePageRef(BaseModel):
    pageNo: int = Field(..., ge=1)
    imageUrl: str | None = None
    imagePath: str | None = None
    extractedText: str | None = None


class RegisterInvoiceRequest(BaseModel):
    invoiceNumber: str = Field(..., min_length=1)
    invoiceDate: str
    storeNumber: str | None = None
    storeName: str | None = None
    address: str | None = None
    subtotal: float = Field(default=0, ge=0)
    tax: float = Field(default=0, ge=0)
    total: float = Field(default=0, ge=0)
    pageCount: int = Field(default=1, ge=1)
    pages: list[InvoicePageRef] = []
    items: list[InvoiceLineItem]
    sourceMode: str = 'manual_review'


class RegisterInvoiceResponse(BaseModel):
    invoiceNumber: str
    status: str
    orderId: str
    createdOrder: bool
    updatedInvoice: bool
    isComplete: bool
    totalsMatch: bool
    newProductsCreated: list[str]
    invoiceDiff: list[str]


class ScanInvoicePagesRequest(BaseModel):
    invoiceNumber: str | None = None
    pages: list[InvoicePageRef]


class ScanInvoicePagesResponse(BaseModel):
    ocrAvailable: bool
    parserMatched: bool
    isComplete: bool
    totalsMatch: bool
    message: str
    extractedTexts: list[str]
    suggestedInvoice: dict[str, object]


class ProcessOrderResponse(BaseModel):
    orderId: str
    status: str
    identificationMode: str
    allowOverhangCm: float
    pallet: PalletRequest
    boxes: list[BoxPlan]
    layout: list[LayoutItem]
    stats: StatsResponse
    palletCount: int
    pallets: list[PalletPlanView]
    packingLog: list[str] = []


class SeedProductsResponse(BaseModel):
    inserted: int
    skus: list[str]

