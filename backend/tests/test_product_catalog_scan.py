from unittest import IsolatedAsyncioTestCase, TestCase
from unittest.mock import AsyncMock, patch

from pydantic import ValidationError

from app.models.schemas import (
    InvoicePageRef,
    ScanInvoicePagesRequest,
    ScanProductCatalogRequest,
)
from app.services.product_catalog_scan_service import (
    ProductCatalogScanError,
    scan_product_catalog,
)


def _product(sku: str = "ABC/123") -> dict[str, object]:
    return {
        "sku": sku,
        "description": "Clear container",
        "secondName": "",
        "category": "Contenedores",
        "brand": "",
        "manufacturer": "",
        "packDescription": "100 count",
        "unitsPerCase": 100,
        "alternateSkus": [],
        "barcode": "",
        "color": "Clear",
        "material": "Plastic",
        "size": "",
    }


class ScanRequestLimitTests(TestCase):
    def test_catalog_scan_rejects_more_than_five_images(self) -> None:
        pages = [
            InvoicePageRef(pageNo=index, imageUrl=f"https://x/{index}")
            for index in range(1, 7)
        ]

        with self.assertRaises(ValidationError):
            ScanProductCatalogRequest(pages=pages)

    def test_invoice_scan_rejects_more_than_five_images(self) -> None:
        pages = [
            InvoicePageRef(pageNo=index, imageUrl=f"https://x/{index}")
            for index in range(1, 7)
        ]

        with self.assertRaises(ValidationError):
            ScanInvoicePagesRequest(pages=pages)


class ProductCatalogScanTests(IsolatedAsyncioTestCase):
    async def test_scan_keeps_products_when_another_image_fails(self) -> None:
        async def extract(
            image_urls: list[str],
            *,
            retry_for_empty: bool = False,
        ) -> dict[str, object]:
            if image_urls == ["https://x/bad"]:
                raise RuntimeError("temporary failure")
            return {"products": [_product()]}

        request = ScanProductCatalogRequest(
            pages=[
                InvoicePageRef(pageNo=1, imageUrl="https://x/good"),
                InvoicePageRef(pageNo=2, imageUrl="https://x/bad"),
            ]
        )
        with (
            patch(
                "app.services.product_catalog_scan_service.extract_catalog_products_from_images_with_ai",
                new=AsyncMock(side_effect=extract),
            ),
            patch(
                "app.services.product_catalog_scan_service.get_product_by_sku",
                return_value=None,
            ),
            patch(
                "app.services.product_catalog_scan_service.create_scanned_catalog_product_if_missing",
                return_value=True,
            ),
        ):
            response = await scan_product_catalog(request)

        self.assertEqual(response.createdSkus, ["ABC/123"])
        self.assertEqual(len(response.products), 1)
        self.assertIn("1 de 2", response.message)

    async def test_empty_first_pass_gets_one_recovery_attempt(self) -> None:
        extract = AsyncMock(
            side_effect=[
                {"products": []},
                {"products": [_product("SKU-2")]},
            ]
        )
        request = ScanProductCatalogRequest(
            pages=[InvoicePageRef(pageNo=1, imageUrl="https://x/one")]
        )
        with (
            patch(
                "app.services.product_catalog_scan_service.extract_catalog_products_from_images_with_ai",
                new=extract,
            ),
            patch(
                "app.services.product_catalog_scan_service.get_product_by_sku",
                return_value={"sku": "SKU-2"},
            ),
        ):
            response = await scan_product_catalog(request)

        self.assertEqual(response.existingSkus, ["SKU-2"])
        self.assertEqual(extract.await_count, 2)
        self.assertTrue(extract.await_args_list[1].kwargs["retry_for_empty"])

    async def test_scan_raises_friendly_error_when_every_attempt_fails(self) -> None:
        request = ScanProductCatalogRequest(
            pages=[InvoicePageRef(pageNo=1, imageUrl="https://x/one")]
        )
        with patch(
            "app.services.product_catalog_scan_service.extract_catalog_products_from_images_with_ai",
            new=AsyncMock(side_effect=RuntimeError("provider unavailable")),
        ):
            with self.assertRaises(ProductCatalogScanError):
                await scan_product_catalog(request)
