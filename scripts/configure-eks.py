"""Render non-secret AWS configuration from Terraform outputs."""
import argparse
import json
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("outputs", type=Path)
args = parser.parse_args()
values = {key: item["value"] for key, item in json.loads(args.outputs.read_text(encoding="utf-8-sig")).items()}
root = Path(__file__).resolve().parents[1]
config = root / "gitops-manifests/aws/config.yaml"
text = config.read_text(encoding="utf-8")
for key, value in {
    "AWS_REGION": values["aws_region"],
    "AWS_SQS_URL": values["sqs_queue_url"],
    "AWS_DYNAMODB_TABLE": values["dynamodb_table_name"],
    "REDIS_URL": values["redis_url"],
}.items():
    text, count = re.subn(rf"(?m)^  {key}: .*", f"  {key}: {json.dumps(value)}", text)
    assert count == 1, key
config.write_text(text, encoding="utf-8")
images = root / "gitops-manifests/aws/kustomization.yaml"
text = images.read_text(encoding="utf-8")
for service, image in values["ecr_repositories"].items():
    text, count = re.subn(rf"(?m)^    newName: [^\n]+/togglemaster/{re.escape(service)}$", f"    newName: {image}", text)
    assert count == 1, service
images.write_text(text, encoding="utf-8")
remote = subprocess.check_output(["git", "remote", "get-url", "origin"], cwd=root, text=True).strip()
if remote.startswith("git@github.com:"):
    remote = remote.replace("git@github.com:", "https://github.com/", 1)
if not re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?", remote):
    raise ValueError("Configure a GitHub HTTPS or SSH origin without embedded credentials")
application = root / "gitops-manifests/argocd/application.yaml"
text = re.sub(r"(?m)^    repoURL: .*", f"    repoURL: {remote}", application.read_text(encoding="utf-8"))
application.write_text(text, encoding="utf-8")
print("AWS ConfigMap, image registries and ArgoCD source updated. No secrets written.")
