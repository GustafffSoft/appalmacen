from unittest import TestCase

from fastapi.testclient import TestClient

from main import app


class ApiSecurityTests(TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.client = TestClient(app)

    def test_health_is_public(self) -> None:
        response = self.client.get("/api/v1/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_products_require_authentication(self) -> None:
        response = self.client.get("/api/v1/products")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers.get("www-authenticate"), "Bearer")

    def test_invoice_scan_requires_authentication(self) -> None:
        response = self.client.post("/api/v1/invoices/scan-pages", json={"pages": []})
        self.assertEqual(response.status_code, 401)

    def test_product_merge_requires_authentication(self) -> None:
        response = self.client.post(
            "/api/v1/products/merge",
            json={"sourceSku": "MAN-TEST", "targetSku": "REAL-TEST"},
        )
        self.assertEqual(response.status_code, 401)
