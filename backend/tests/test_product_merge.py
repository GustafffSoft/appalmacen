from unittest import TestCase

from app.services.firebase_service import (
    _build_product_merge_payload,
    _is_manual_product,
    _product_document_id,
)


class ProductMergeTests(TestCase):
    def test_product_document_id_preserves_normal_skus(self) -> None:
        self.assertEqual(_product_document_id(" 936833 "), "936833")

    def test_product_document_id_encodes_skus_with_slashes(self) -> None:
        document_id = _product_document_id("abc/123")

        self.assertNotIn("/", document_id)
        self.assertEqual(document_id, "__SKU_B64__QUJDLzEyMw")
        self.assertEqual(document_id, _product_document_id("ABC/123"))
        self.assertNotEqual(document_id, _product_document_id("ABC/124"))

    def test_manual_product_detection_uses_sku_or_creation_source(self) -> None:
        self.assertTrue(_is_manual_product("MAN-ABC", {}))
        self.assertTrue(
            _is_manual_product(
                "TEMP-ABC",
                {"creationSource": "warehouse_pallet_entry"},
            )
        )
        self.assertFalse(_is_manual_product("936833", {"source": "invoice"}))

    def test_merge_payload_preserves_aliases_and_adds_stock(self) -> None:
        payload = _build_product_merge_payload(
            "MAN-ABC",
            {
                "name": "Vaso manual",
                "secondName": "Vaso provisional",
                "alternateNames": ["Vaso Manual"],
                "alternateSkus": ["OLD-ABC"],
                "stockQty": 12,
            },
            "936833",
            {
                "name": "16J16 Dart 16 oz Foam Cup",
                "alternateNames": ["Foam cup"],
                "alternateSkus": ["QDART936833"],
                "stockQty": 5,
            },
        )

        self.assertEqual(payload["stockQty"], 17)
        self.assertEqual(
            payload["alternateNames"],
            ["Foam cup", "Vaso manual", "Vaso provisional"],
        )
        self.assertEqual(
            payload["alternateSkus"],
            ["QDART936833", "MAN-ABC", "OLD-ABC"],
        )
