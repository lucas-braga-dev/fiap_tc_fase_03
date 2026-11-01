"""Issue the Evaluation API key through a local kubectl port-forward."""
import base64
import json
import subprocess
import urllib.request

raw = subprocess.check_output(["kubectl", "get", "secret", "togglemaster-secrets", "-n", "togglemaster", "-o", "json"])
secret = json.loads(raw)
master = base64.b64decode(secret["data"]["MASTER_KEY"]).decode()
request = urllib.request.Request(
    "http://127.0.0.1:18001/admin/keys",
    data=json.dumps({"name": "evaluation-service"}).encode(),
    headers={"Authorization": "Bearer " + master, "Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(request, timeout=10) as response:
    key = json.load(response)["key"]
# Use stdin, not command-line arguments or a file containing credentials.
patch = {"apiVersion": "v1", "kind": "Secret",
         "metadata": {"name": "togglemaster-secrets", "namespace": "togglemaster"},
         "type": "Opaque", "data": {**secret["data"], "SERVICE_API_KEY": base64.b64encode(key.encode()).decode()}}
subprocess.run(["kubectl", "apply", "-f", "-"], input=json.dumps(patch).encode(), check=True)
subprocess.run(["kubectl", "rollout", "restart", "deployment/evaluation-service", "-n", "togglemaster"], check=True)
subprocess.run(["kubectl", "rollout", "status", "deployment/evaluation-service", "-n", "togglemaster", "--timeout=3m"], check=True)
print("SERVICE_API_KEY issued and Evaluation updated; MASTER_KEY preserved.")
