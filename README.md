# gitops-trustplane

A repeatable Docker Desktop Kubernetes GitOps PoC for Authentik, OpenBao, Step CA, and ingress-nginx. Run the install script once to bootstrap Argo CD; Argo CD then installs and reconciles the stack from this repository using an app-of-apps layout.

> PoC only, not production-hardened. Example credentials are committed in values files and are suitable only for disposable local testing. OpenBao is standalone, and the CA is not configured for production key protection.

## Prerequisites

- Docker Desktop Kubernetes enabled and selected in the current `kubectl` context
- Docker Desktop provisioned with enough CPU and memory for all components (start with at least 4 CPUs and 6 GiB RAM)
- `kubectl`, OpenSSL 1.1.1 or later, and network access to GitHub and the Helm chart repositories
- This repository accessible to the cluster's Argo CD instance (it is public; configure repository credentials if you make it private)

## Bootstrap and deploy

From the repository root:

```sh
./scripts/install.sh
```

This wrapper runs `scripts/bootstrap-argocd.sh`, which installs the pinned Argo CD release into `argocd`, configures its server for HTTP behind the local TLS-terminating ingress, waits for the server, then applies `argocd/root-application.yaml`. Override the Argo CD version with `ARGOCD_VERSION` if desired, for example `ARGOCD_VERSION=v3.0.0 ./scripts/install.sh`. The root Application discovers child Applications in `argocd/applications/`; those install pinned Helm chart versions and apply the Ingress resources. Argo CD continuously reconciles changes from `main`.

To monitor:

```sh
kubectl -n argocd get applications
kubectl -n trust-plane get pods,svc,ingress
```

## Local UI access and TLS

Map the local hostnames to `127.0.0.1` in your hosts file. These names are intended for local access only; do not configure router port forwarding or expose the ingress controller externally.

```text
127.0.0.1 argocd.myorg.local authentik.myorg.local openbao.myorg.local step-ca.myorg.local
```

`.local` can conflict with mDNS on some systems; if resolution is unreliable, use a reserved testing suffix such as `.test` and update the Ingress manifests and hosts file consistently.

The Ingresses use TLS. The following commands create a local CA and a certificate covering all four hostnames with OpenSSL. Run from the repository root. Keep the CA private key secure and never commit the `local-tls/` directory or its private keys.

```sh
mkdir -p local-tls
umask 077

# Create a local certificate authority.
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout local-tls/local-ca.key \
  -out local-tls/local-ca.crt \
  -subj "/CN=gitops-trustplane local CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# Create a server key and certificate signing request.
openssl req -new -newkey rsa:2048 -nodes \
  -keyout local-tls/myorg-local.key \
  -out local-tls/myorg-local.csr \
  -subj "/CN=argocd.myorg.local"

# Add subject alternative names for each local UI hostname.
cat > local-tls/myorg-local.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:argocd.myorg.local,DNS:authentik.myorg.local,DNS:openbao.myorg.local,DNS:step-ca.myorg.local
EOF

# Sign the server certificate with the local CA.
openssl x509 -req -in local-tls/myorg-local.csr \
  -CA local-tls/local-ca.crt -CAkey local-tls/local-ca.key -CAcreateserial \
  -out local-tls/myorg-local.crt -days 825 -sha256 \
  -extfile local-tls/myorg-local.ext
```

Trust `local-tls/local-ca.crt` on your computer to avoid browser certificate warnings. On macOS, import it into Keychain Access and set the trust policy for local testing; on Linux, use your distribution's system CA trust procedure. Some browsers maintain a separate certificate store. Do not distribute or commit `local-ca.key`.

Run the install script first so the `argocd` namespace exists, then create the TLS Secret in both namespaces. Kubernetes Secrets are namespace-scoped. The `trust-plane` namespace is created here if it does not exist yet:

```sh
kubectl -n argocd create secret tls myorg-local-tls \
  --cert=local-tls/myorg-local.crt --key=local-tls/myorg-local.key
kubectl create namespace trust-plane --dry-run=client -o yaml | kubectl apply -f -
kubectl -n trust-plane create secret tls myorg-local-tls \
  --cert=local-tls/myorg-local.crt --key=local-tls/myorg-local.key
```

Open the UIs at:

- <https://argocd.myorg.local>
- <https://authentik.myorg.local>
- <https://openbao.myorg.local>
- <https://step-ca.myorg.local>

Argo CD's initial admin password can be retrieved with:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Log in as `admin` and change the password. Keep this port-forward as a local recovery option if Ingress is unavailable:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## Updating and removing

Commit changes to Git; Argo CD detects them and applies the desired state. Avoid running direct Helm commands against releases managed by Argo CD, since that creates competing release owners. To remove the PoC, delete the root Application and then remove Argo CD and the namespace deliberately; deleting PVCs can delete local state.

## Layout

- `scripts/install.sh` — user-facing entry point that bootstraps Argo CD.
- `scripts/bootstrap-argocd.sh` — installs Argo CD and applies the root Application.
- `argocd/root-application.yaml` — app-of-apps entry point.
- `argocd/applications/` — child Applications for ingress-nginx, the apps, and Ingress manifests.
- `components/*/values.yaml` — chart settings used by the Helm Applications.
- `manifests/` — namespace and Ingress resources, including local Argo CD access.

Chart versions are pinned in child Application manifests for repeatability. Review and update chart versions intentionally; validate chart values against the selected versions before upgrading.
