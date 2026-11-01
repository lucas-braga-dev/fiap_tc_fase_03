import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("images", ROOT / "scripts/update-gitops-images.py")
images = importlib.util.module_from_spec(spec)
spec.loader.exec_module(images)


class ImageUpdateTests(unittest.TestCase):
    def setUp(self):
        self.text = (ROOT / "gitops-manifests/aws/kustomization.yaml").read_text(encoding="utf-8")
        self.registry = "123456789012.dkr.ecr.us-east-2.amazonaws.com"

    def test_updates_all_five_images_and_is_idempotent(self):
        result = images.update_images(self.text, self.registry, "a" * 40)
        self.assertEqual(result.count("newTag: " + "a" * 40), 5)
        for service in images.SERVICES:
            self.assertIn(f"newName: {self.registry}/togglemaster/{service}", result)
        self.assertEqual(images.update_images(result, self.registry, "a" * 40), result)

    def test_rejects_missing_service_and_leaves_input_unchanged(self):
        original = self.text
        with self.assertRaises(ValueError):
            images.update_images(self.text.replace("  - name: togglemaster/auth-service", "  - name: other"), self.registry, "a" * 40)
        self.assertEqual(self.text, original)

    def test_rejects_invalid_registry_and_tag(self):
        for registry, tag in [("bad.example.com", "a" * 40), (self.registry, "latest"), (self.registry, "x\nrun")]:
            with self.assertRaises(ValueError):
                images.update_images(self.text, registry, tag)


if __name__ == "__main__":
    unittest.main()
