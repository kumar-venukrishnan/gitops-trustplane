# gitops-trustplane

A repeatable Docker Desktop Kubernetes GitOps PoC for Authentik, OpenBao, Step CA, and ingress-nginx. Install Argo CD once with the bootstrap script; Argo CD then installs and reconciles the stack from this repository using an app-of-apps layout.

> PoC only, not production-hardened. Example credentials are committed in the values files and must be replaced for any environment beyond disposable local testing. OpenBao is standalone, and the CA is not configured for production key protection.

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

The script installs a pinned Argo CD release into `argocd` (override `ARGOCD_VERSION` if desired), waits for its server deployment, then applies `argocd/root-application.yaml`. The root Application discovers the child Applications in `argocd/applications/`; those Applications install pinned Helm chart versions and apply the Ingress resources. Argo CD will continuously reconcile changes from the `main` branch.

To monitor:

```sh
kubectl -n argocd get applications
kubectl -n trust-plane get pods,svc,ingress
```

To open the Argo CD UI locally:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Retrieve the initial admin password (change it after logging in):

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \\
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Visit `https://localhost:8080` and log in as `admin`.

## Local hostnames

Map these names to `127.0.0.1` in your hosts file. Docker Desktop's LoadBalancer service is expected to be reachable locally:

```text
127.0.0.1 authentik.myorg.local openbao.myorg.local step-ca.myorg.local
```

The Ingresses reference TLS Secret `myorg-local-tls` in `trust-plane`. For initial HTTP-only testing, remove the `tls` sections in `manifests/ingress/`; for HTTPS, create that Secret with a certificate whose SANs cover all three names. Do not commit private keys.

## Updating and removing

Commit changes to Git; Argo CD detects them and applies the desired state. Avoid running the old direct Helm install flow alongside Argo CD, since that would create competing release owners. To remove the PoC, delete the root Application and then remove Argo CD and the namespace deliberately; PVC cleanup can delete local state.

## Layout

- `scripts/bootstrap-argocd.sh` — installs Argo CD and applies the root Application.
- `argocd/root-application.yaml` — app-of-apps entry point.
- `argocd/applications/` — child Applications for ingress-nginx, the apps, and Ingress manifests.
- `components/*/values.yaml` — chart settings used by the Helm Applications.
- `manifests/` — namespace and Ingress resources.

Chart versions are pinned in the child Application manifests for repeatability. Review and update chart versions intentionally; validate chart values against the selected versions before upgrading.
