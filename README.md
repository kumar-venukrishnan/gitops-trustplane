# gitops-trustplane

A repeatable Docker Desktop Kubernetes GitOps PoC for Authentik, OpenBao, Step CA, and ingress-nginx. Bootstrap Argo CD once; Argo CD then installs and reconciles the stack from this repository using an app-of-apps layout.

> PoC only, not production-hardened. Example credentials are committed in values files and are suitable only for disposable local testing. OpenBao is standalone, and the CA is not configured for production key protection.

## Prerequisites

- Docker Desktop Kubernetes enabled and selected in the current `kubectl` context
- Docker Desktop provisioned with enough CPU and memory for all components (start with at least 4 CPUs and 6 GiB RAM)
- `kubectl` and network access to GitHub and the Helm chart repositories
- This repository accessible to the cluster's Argo CD instance (it is public; configure repository credentials if you make it private)

## Bootstrap and deploy

From the repository root:

```sh
./scripts/bootstrap-argocd.sh
```

The script installs a pinned Argo CD release into `argocd`, configures its server for HTTP behind the local TLS-terminating ingress, waits for the server, then applies `argocd/root-application.yaml`. Override the Argo CD version with `ARGOCD_VERSION` if desired. The root Application discovers child Applications in `argocd/applications/`; those install pinned Helm chart versions and apply the Ingress resources. Argo CD continuously reconciles changes from `main`.

To monitor:

```sh
kubectl -n argocd get applications
kubectl -n trust-plane get pods,svc,ingress
```

## Local UI access

Map the local hostnames to `127.0.0.1` in your hosts file. These names are intended for local access only; do not configure router port forwarding or expose the ingress controller externally.

```text
127.0.0.1 argocd.myorg.local authentik.myorg.local openbao.myorg.local step-ca.myorg.local
```

`.local` can conflict with mDNS on some systems; if resolution is unreliable, use a reserved testing suffix such as `.test` and update the Ingress manifests and hosts file consistently.

The Ingresses use TLS. Create a locally trusted certificate (for example, with `mkcert`) covering all four hostnames. Kubernetes Secrets are namespace-scoped, so create one copy in each namespace:

```sh
mkcert argocd.myorg.local authentik.myorg.local openbao.myorg.local step-ca.myorg.local

kubectl -n argocd create secret tls myorg-local-tls \\
  --cert=argocd.myorg.local+3.pem --key=argocd.myorg.local+3-key.pem
kubectl create namespace trust-plane --dry-run=client -o yaml | kubectl apply -f -
kubectl -n trust-plane create secret tls myorg-local-tls \\
  --cert=argocd.myorg.local+3.pem --key=argocd.myorg.local+3-key.pem
```

Run those Secret commands after bootstrap has created `argocd` and before the apps' Ingresses are used. If the generated mkcert filenames differ, use the actual filenames. Do not commit certificate private keys.

Open the UIs at:

- <https://argocd.myorg.local>
- <https://authentik.myorg.local>
- <https://openbao.myorg.local>
- <https://step-ca.myorg.local>

Argo CD's initial admin password can be retrieved with:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \\
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Log in as `admin` and change the password. Keep this port-forward as a local recovery option if Ingress is unavailable:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## Updating and removing

Commit changes to Git; Argo CD detects them and applies the desired state. Avoid running direct Helm commands against releases managed by Argo CD, since that creates competing release owners. To remove the PoC, delete the root Application and then remove Argo CD and the namespace deliberately; deleting PVCs can delete local state.

## Layout

- `scripts/bootstrap-argocd.sh` — installs Argo CD and applies the root Application.
- `argocd/root-application.yaml` — app-of-apps entry point.
- `argocd/applications/` — child Applications for ingress-nginx, the apps, and Ingress manifests.
- `components/*/values.yaml` — chart settings used by the Helm Applications.
- `manifests/` — namespace and Ingress resources, including local Argo CD access.

Chart versions are pinned in child Application manifests for repeatability. Review and update chart versions intentionally; validate chart values against the selected versions before upgrading.
