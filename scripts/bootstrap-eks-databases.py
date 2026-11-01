"""Initialize three RDS databases inside EKS; never write passwords to disk."""
import base64
import json
import secrets
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

root = Path(__file__).resolve().parents[1]
values = {k: v["value"] for k, v in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig")).items()}


def command(*args, data=None, capture=False):
    return subprocess.run(args, input=data, stdout=subprocess.PIPE if capture else None, check=True)


def apply(document):
    command("kubectl", "apply", "-f", "-", data=json.dumps(document).encode())


def secret(name, values):
    apply({"apiVersion": "v1", "kind": "Secret", "metadata": {"name": name, "namespace": "togglemaster"},
           "type": "Opaque", "data": {k: base64.b64encode(v.encode()).decode() for k, v in values.items()}})


def url(user, password, db):
    return f"postgres://{quote(user, safe='')}:{quote(password, safe='')}@{db['host']}:5432/{db['database']}?sslmode=require"


# Prevent accidental password rotation or loss of an existing SERVICE_API_KEY.
existing = command("kubectl", "get", "secret", "togglemaster-secrets", "-n", "togglemaster", "--ignore-not-found", "-o", "json", capture=True).stdout
if existing.strip():
    raise SystemExit("Secret togglemaster-secrets already exists. Stop: preserve existing passwords and migrate explicitly.")
master = {}
apps = {"MASTER_KEY": secrets.token_hex(32), "SERVICE_API_KEY": "PENDENTE_PRIMEIRO_DEPLOY"}
for name, db in values["rds"].items():
    response = command("aws", "secretsmanager", "get-secret-value", "--secret-id", db["master_secret_arn"],
                       "--region", values["aws_region"], "--query", "SecretString", "--output", "text", capture=True)
    credential = json.loads(response.stdout)
    password = secrets.token_urlsafe(32)
    key = name.upper()
    master[key + "_MASTER_URL"] = url(credential["username"], credential["password"], db)
    master[key + "_PASSWORD"] = password
    apps[key + "_DATABASE_URL"] = url(name + "_user", password, db)
schema_paths = {
    "auth.sql": root / "apps-togglemaster/src/auth-service/db/init.sql",
    "flags.sql": root / "apps-togglemaster/src/flag-service/db/init.sql",
    "targeting.sql": root / "apps-togglemaster/src/targeting-service/db/init.sql",
    "grants.sql": root / "deploy/eks/grants.sql",
}
apply({"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "togglemaster-db-schemas", "namespace": "togglemaster"},
       "data": {k: p.read_text(encoding="utf-8") for k, p in schema_paths.items()}})
secret("togglemaster-db-bootstrap", master)
command("kubectl", "delete", "job", "togglemaster-db-bootstrap", "-n", "togglemaster", "--ignore-not-found", "--wait=true")
command("kubectl", "apply", "-f", str(root / "deploy/eks/bootstrap-job.yaml"))
command("kubectl", "wait", "-n", "togglemaster", "--for=condition=complete", "job/togglemaster-db-bootstrap", "--timeout=10m")
# Publish application credentials only after all schemas and grants succeeded.
secret("togglemaster-secrets", apps)
command("kubectl", "delete", "job", "togglemaster-db-bootstrap", "-n", "togglemaster", "--wait=true")
command("kubectl", "delete", "secret", "togglemaster-db-bootstrap", "-n", "togglemaster")
print("Three databases initialized; application Secret created; temporary master Secret removed.")
