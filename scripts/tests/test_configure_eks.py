import json
import runpy
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class ConfigureEksTests(unittest.TestCase):
    def test_personal_account_configuration_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ["scripts/configure-eks.py", "gitops-manifests/aws/config.yaml", "gitops-manifests/aws/kustomization.yaml", "gitops-manifests/argocd/application.yaml"]:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            values = {
                "aws_region": "us-east-2", "sqs_queue_url": "https://sqs.us-east-2.amazonaws.com/123456789012/events",
                "dynamodb_table_name": "analytics", "redis_url": "rediss://redis.internal:6379",
                "ecr_repositories": {name: f"123456789012.dkr.ecr.us-east-2.amazonaws.com/togglemaster/{name}" for name in ["auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service"]},
            }
            outputs = root / "outputs.json"
            outputs.write_text(json.dumps({key: {"value": value} for key, value in values.items()}), encoding="utf-8")
            with patch.object(sys, "argv", ["configure-eks.py", str(outputs)]), patch("subprocess.check_output", return_value="git@github.com:example/repo.git\n"):
                runpy.run_path(str(root / "scripts/configure-eks.py"), run_name="__main__")
                initial = (root / "gitops-manifests/aws/kustomization.yaml").read_text()
                runpy.run_path(str(root / "scripts/configure-eks.py"), run_name="__main__")
            self.assertEqual(initial, (root / "gitops-manifests/aws/kustomization.yaml").read_text())
            self.assertNotIn("components:", initial)
            self.assertFalse((root / "gitops-manifests/aws/identity").exists())
            source = (root / "gitops-manifests/argocd/application.yaml").read_text()
            self.assertIn("repoURL: https://github.com/example/repo.git", source)

    def test_database_bootstrap_refuses_to_rotate_existing_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            outputs = Path(directory) / "outputs.json"
            outputs.write_text("{}", encoding="utf-8")
            with patch.object(sys, "argv", ["bootstrap-eks-databases.py", str(outputs)]), patch("subprocess.run") as command:
                command.return_value.stdout = b'{"metadata":{"name":"togglemaster-secrets"}}'
                with self.assertRaisesRegex(SystemExit, "already exists"):
                    runpy.run_path(str(ROOT / "scripts/bootstrap-eks-databases.py"), run_name="__main__")
                command.assert_called_once()
                self.assertEqual(command.call_args.args[0][:3], ("kubectl", "get", "secret"))


if __name__ == "__main__":
    unittest.main()
