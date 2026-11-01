import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import requests


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with patch.dict(os.environ, {"DATABASE_URL": "postgres://unused", "AUTH_SERVICE_URL": "http://auth"}), patch("psycopg2.pool.SimpleConnectionPool"):
            spec = importlib.util.spec_from_file_location("api_test_app", Path(__file__).with_name("app.py"))
            cls.module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.module)
        cls.client = cls.module.app.test_client()

    def test_health_is_public(self):
        self.assertEqual(self.client.get("/health").status_code, 200)

    def test_protected_endpoint_rejects_missing_key(self):
        self.assertEqual(self.client.get("/flags").status_code, 401)

    @patch("requests.get", return_value=MagicMock(status_code=401))
    def test_protected_endpoint_rejects_invalid_key(self, auth):
        response = self.client.get("/flags", headers={"Authorization": "Bearer wrong"})
        self.assertEqual(response.status_code, 401)

    @patch("requests.get", side_effect=requests.exceptions.Timeout)
    def test_auth_timeout_returns_gateway_timeout(self, auth):
        response = self.client.get("/flags", headers={"Authorization": "Bearer key"})
        self.assertEqual(response.status_code, 504)


if __name__ == "__main__":
    unittest.main()
