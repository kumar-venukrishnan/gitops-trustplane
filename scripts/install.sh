#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="trust-plane"

for command in kubectl helm kustomize; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 1; }
done

kubectl cluster-info >/dev/null

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo add authentik https://charts.goauthentik.io --force-update
helm repo add openbao https://openbao.github.io/openbao-helm-charts --force-update
helm repo add smallstep https://smallstep.github.io/helm-charts --force-update
helm repo update

kubectl apply -f "$ROOT_DIR/namespace.yaml"

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace "$NAMESPACE" --create-namespace \
  --values "$ROOT_DIR/components/ingress-nginx/values.yaml" --wait

helm upgrade --install authentik authentik/authentik \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/components/authentik/values.yaml" --wait

helm upgrade --install openbao openbao/openbao \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/components/openbao/values.yaml" --wait

helm upgrade --install step-ca smallstep/step-certificates \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/components/step-ca/values.yaml" --wait

kustomize build "$ROOT_DIR" | kubectl apply -f -

echo "Installed trust-plane charts. Check services and Ingresses with: kubectl -n $NAMESPACE get pods,svc,ingress"
