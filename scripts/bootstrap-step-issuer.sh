#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${STEP_CA_NAMESPACE:-trust-plane}"
PROVISIONER_NAME="${STEP_CA_PROVISIONER_NAME:-admin}"
CA_CONFIGMAP="${STEP_CA_CONFIGMAP:-step-ca-step-certificates-config}"
CA_CERTS_CONFIGMAP="${STEP_CA_CERTS_CONFIGMAP:-step-ca-step-certificates-certs}"
CA_PASSWORD_SECRET="${STEP_CA_PASSWORD_SECRET:-step-ca-step-certificates-provisioner-password}"
ISSUER_PASSWORD_SECRET="${STEP_ISSUER_PASSWORD_SECRET:-step-issuer-provisioner-password}"
ISSUER_NAME="${STEP_CLUSTER_ISSUER_NAME:-step-ca}"
CA_URL="${STEP_CA_URL:-https://step-ca-step-certificates.${NAMESPACE}.svc.cluster.local}"

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

for _ in $(seq 1 120); do
  if kubectl -n "$NAMESPACE" get configmap "$CA_CONFIGMAP" >/dev/null 2>&1 \
    && kubectl -n "$NAMESPACE" get configmap "$CA_CERTS_CONFIGMAP" >/dev/null 2>&1 \
    && kubectl -n "$NAMESPACE" get secret "$CA_PASSWORD_SECRET" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

kubectl -n "$NAMESPACE" get configmap "$CA_CONFIGMAP" >/dev/null
kubectl -n "$NAMESPACE" get configmap "$CA_CERTS_CONFIGMAP" >/dev/null
kubectl -n "$NAMESPACE" get secret "$CA_PASSWORD_SECRET" >/dev/null

CURRENT_SECRET_JSON=$(kubectl -n "$NAMESPACE" get secret "$CA_PASSWORD_SECRET" -o json)
python3 - "$CURRENT_SECRET_JSON" "$ISSUER_PASSWORD_SECRET" "$NAMESPACE" <<'PY' | kubectl apply -f -
import json, sys
secret = json.loads(sys.argv[1])
name = sys.argv[2]
namespace = sys.argv[3]
secret["metadata"] = {"name": name, "namespace": namespace}
secret.pop("status", None)
secret["type"] = "Opaque"
print(json.dumps(secret))
PY

CONFIG_JSON="$(kubectl -n "$NAMESPACE" get configmap "$CA_CONFIGMAP" -o json)"
CERTS_JSON="$(kubectl -n "$NAMESPACE" get configmap "$CA_CERTS_CONFIGMAP" -o json)"
python3 - "$CONFIG_JSON" "$CERTS_JSON" "$PROVISIONER_NAME" "$ISSUER_NAME" "$NAMESPACE" "$CA_URL" "$ISSUER_PASSWORD_SECRET" <<'PY' | kubectl apply -f -
import base64, json, sys
config_data = json.loads(sys.argv[1])
certs_data = json.loads(sys.argv[2])
provisioner_name = sys.argv[3]
issuer_name = sys.argv[4]
namespace = sys.argv[5]
ca_url = sys.argv[6]
password_secret = sys.argv[7]
ca_config = json.loads(config_data["data"]["ca.json"])
root = certs_data["data"].get("root_ca.crt")
if not root:
    raise SystemExit("Step CA root_ca.crt was not found in its certs ConfigMap")
provisioners = ca_config.get("authority", {}).get("provisioners", [])
provisioner = next((p for p in provisioners if p.get("name") == provisioner_name), None)
if not provisioner:
    raise SystemExit(f"Step CA provisioner {provisioner_name!r} was not found in ca.json")
kid = (provisioner.get("key") or {}).get("kid")
if not kid:
    raise SystemExit(f"JWK kid for provisioner {provisioner_name!r} was not found in ca.json")
issuer = {
    "apiVersion": "certmanager.step.sm/v1beta1",
    "kind": "StepClusterIssuer",
    "metadata": {"name": issuer_name},
    "spec": {
        "url": ca_url,
        "caBundle": base64.b64encode(root.encode()).decode(),
        "provisioner": {
            "name": provisioner_name,
            "kid": kid,
            "passwordRef": {
                "name": password_secret,
                "namespace": namespace,
                "key": "password",
            },
        },
    },
}
print(json.dumps(issuer))
PY

echo "Applied StepClusterIssuer/${ISSUER_NAME}." 
