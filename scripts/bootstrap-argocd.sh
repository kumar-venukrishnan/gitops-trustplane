#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.0.0}"

command -v kubectl >/dev/null 2>&1 || { echo "Missing required command: kubectl" >&2; exit 1; }
kubectl cluster-info >/dev/null

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl apply -f "$ROOT_DIR/manifests/argocd/argocd-cmd-params-cm.yaml"
kubectl -n argocd rollout restart deployment/argocd-server
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
kubectl apply -f "$ROOT_DIR/argocd/root-application.yaml"

echo "Argo CD is bootstrapped. Monitor with: kubectl -n argocd get applications"
