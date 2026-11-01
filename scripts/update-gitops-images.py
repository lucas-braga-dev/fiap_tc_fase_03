"""Update only AWS image references; used by CI after all images pass scans."""
import argparse
import re
from pathlib import Path

SERVICES = ("auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service")


def update_images(text, registry, tag):
    if not re.fullmatch(r"[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com", registry):
        raise ValueError("Invalid private ECR registry")
    if not re.fullmatch(r"[0-9a-f]{40}", tag):
        raise ValueError("Image tag must be the full commit SHA")
    for service in SERVICES:
        pattern = rf"(  - name: togglemaster/{service}\n)    newName: [^\n]+\n    newTag: [^\n]+"
        text, count = re.subn(pattern, rf"\g<1>    newName: {registry}/togglemaster/{service}\n    newTag: {tag}", text)
        if count != 1:
            raise ValueError(f"Expected exactly one image entry for {service}")
    return text


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--path", type=Path, default=Path("gitops-manifests/aws/kustomization.yaml"))
    args = parser.parse_args()
    args.path.write_text(update_images(args.path.read_text(encoding="utf-8"), args.registry, args.tag), encoding="utf-8")
