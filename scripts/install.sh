#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Direct Helm installation is replaced by Argo CD. Running the GitOps bootstrap instead."
exec "$SCRIPT_DIR/bootstrap-argocd.sh" "$@"
