# gitops-trustplane

A repeatable Docker Desktop Kubernetes GitOps PoC for Authentik, OpenBao, Step CA, and ingress-nginx. The install script bootstraps Argo CD; Argo CD installs and reconciles the stack from this repository.

> PoC only, not production-hardened. Example credentials in values files are for disposable local testing. OpenBao is standalone and uses Shamir sealing; protect its initialization keys and root token. The CA is not configured for production key protection.

## Prerequisites

- Docker Desktop Kubernetes enabled and selected in the current `kubectl` context.
- At least 4 CPUs and 6 GiB RAM allocated to Docker Desktop.
- `kubectl`, OpenSSL 1.1.1+, and network access to GitHub and the Helm chart repositories.
- This repository accessible to Argo CD (configure repository credentials if private).

## Bootstrap and deploy

From the repository root:

```sh
./scripts/install.sh
kubectl -n argocd get applications
kubectl -n trust-plane get pods,svc,ingress
```

The script installs the pinned Argo CD release and applies the root Application. Argo CD then discovers child Applications and reconciles changes from `main`. Avoid running Helm commands directly against Argo CD-managed releases.

## Local UI access and TLS

Map local hostnames to `127.0.0.1` in your hosts file. Do not expose the ingress externally:

```text
127.0.0.1 argocd.myorg.local authentik.myorg.local openbao.myorg.local step-ca.myorg.local
```

`.local` may conflict with mDNS; use a reserved testing suffix such as `.test` if needed and update the Ingress manifests and hosts file consistently.

Create a local CA and certificate for the four hostnames (run from the repository root):

```sh
mkdir -p local-tls
umask 077
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout local-tls/local-ca.key -out local-tls/local-ca.crt \
  -subj "/CN=gitops-trustplane local CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
openssl req -new -newkey rsa:2048 -nodes \
  -keyout local-tls/myorg-local.key -out local-tls/myorg-local.csr \
  -subj "/CN=argocd.myorg.local"
cat > local-tls/myorg-local.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:argocd.myorg.local,DNS:authentik.myorg.local,DNS:openbao.myorg.local,DNS:step-ca.myorg.local
EOF
openssl x509 -req -in local-tls/myorg-local.csr \
  -CA local-tls/local-ca.crt -CAkey local-tls/local-ca.key -CAcreateserial \
  -out local-tls/myorg-local.crt -days 825 -sha256 \
  -extfile local-tls/myorg-local.ext
```

Trust `local-tls/local-ca.crt` on your computer. After running the install script, create TLS Secrets in both namespaces:

```sh
kubectl -n argocd create secret tls myorg-local-tls \
  --cert=local-tls/myorg-local.crt --key=local-tls/myorg-local.key
kubectl create namespace trust-plane --dry-run=client -o yaml | kubectl apply -f -
kubectl -n trust-plane create secret tls myorg-local-tls \
  --cert=local-tls/myorg-local.crt --key=local-tls/myorg-local.key
```

Open the UIs at <https://argocd.myorg.local>, <https://authentik.myorg.local>, <https://openbao.myorg.local>, and <https://step-ca.myorg.local>.

Argo CD's initial admin password is available with:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Log in as `admin` and change it. For local recovery if Ingress is unavailable:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## Authentik administrator

On a new deployment, visit <https://authentik.myorg.local/if/flow/initial-setup/> and complete the setup flow to create the initial administrator. If you need to recover the default `akadmin` account password, generate a one-time recovery link from the server pod:

```sh
kubectl -n trust-plane exec deployment/authentik-server -- \
  ak create_recovery_key 10 akadmin
```

Open the URL printed by the command and set a new password. Treat the URL as a secret; do not commit or share it.

## OpenBao initialization and unsealing

OpenBao starts uninitialized and unsealed state is required for readiness. Initialize it once, after the pod is running:

```sh
kubectl -n trust-plane exec -it openbao-0 -- \
  bao operator init -key-shares=5 -key-threshold=3
```

Securely store the five generated unseal keys and initial root token outside Git. To unseal, run the following command three times and enter a different saved key each time:

```sh
kubectl -n trust-plane exec -it openbao-0 -- bao operator unseal
```

Verify with `kubectl -n trust-plane exec openbao-0 -- bao status`. OpenBao seals again after a pod restart; repeat the unseal steps, but **do not initialize again**. Never delete its PVC unless you intend to discard its data. This manual Shamir process is for the local PoC, not production.

## Updating and removing

Commit changes to Git; Argo CD detects and applies the desired state. To remove the PoC, delete the root Application, then remove Argo CD and the namespace deliberately; deleting PVCs can delete local state.

## Layout

- `scripts/install.sh` — user-facing bootstrap entry point.
- `scripts/bootstrap-argocd.sh` — installs Argo CD and applies the root Application.
- `argocd/root-application.yaml` — app-of-apps entry point.
- `argocd/applications/` — child Applications.
- `components/*/values.yaml` — Helm chart settings.
- `manifests/` — namespace and Ingress resources.

Chart versions are pinned in child Application manifests. Review and update versions intentionally, validating chart values against the selected versions.
