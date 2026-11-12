# GitOps trust plane (local PoC)

A Docker Desktop Kubernetes PoC managed by Argo CD for ingress-nginx, Step CA, cert-manager, Authentik, and OpenBao. The existing Helm chart versions and application values are retained; child Applications are split into individual manifests and ordered by Argo CD sync wave.

> **PoC only, not production-hardened.** Replace example application credentials in the values files before use. Protect OpenBao initialization material and Step CA private keys. Do not expose this local ingress externally.

## Prerequisites

- Docker Desktop Kubernetes enabled and selected in the current `kubectl` context.
- At least 4 CPUs and 6 GiB RAM allocated to Docker Desktop.
- `kubectl`, `python3`, and network access to GitHub and the Helm chart repositories.
- This repository accessible to Argo CD (configure repository credentials if private).

## Deploy

From the repository root:

```sh
./scripts/install.sh
kubectl -n argocd get applications
```

Argo CD installs the children in this order:

| Wave | Components |
| --- | --- |
| 0 | `trust-plane` namespace |
| 1 | ingress-nginx |
| 2 | Step CA |
| 3 | cert-manager and Smallstep Step Issuer controller/CRDs |
| 4 | Step CA-backed Certificate resources |
| 5 | Authentik and OpenBao |
| 6 | Authentik, OpenBao, and Argo CD Ingresses |

### Bootstrap the Step CA issuer credentials

The Step CA chart creates its root certificate and provisioner password during initial bootstrap. After the Step CA Application and Step Issuer controller are healthy, run this script locally with a `kubectl` context that can administer the cluster:

```sh
./scripts/bootstrap-step-issuer.sh
```

The script reads the generated CA root, provisioner password, and provisioner key ID from the cluster; creates a dedicated Kubernetes Secret for the issuer password; and applies the `StepClusterIssuer`. It does not print or commit the password. It waits for the Step CA bootstrap resources and can be re-run if needed.

Check issuer status before relying on certificates:

```sh
kubectl get stepclusterissuer step-ca
kubectl -n trust-plane get certificates
kubectl -n trust-plane get secrets authentik-tls openbao-tls
kubectl -n argocd get secret argocd-tls
```

The `Certificate` resources cause cert-manager to create the workload TLS Secrets; do not create those TLS Secrets manually. Because the issuer is bootstrapped locally, it is not itself reconciled from Git. Re-run the bootstrap script if the issuer or its credential Secret is removed.

### Local hostnames and CA trust

Add these host mappings to your local hosts file:

```text
127.0.0.1 argocd.myorg.local authentik.myorg.local openbao.myorg.local
```

Trust the Step CA root certificate on your computer to avoid browser certificate warnings. Retrieve the public root certificate with:

```sh
kubectl -n trust-plane get configmap step-ca-step-certificates-certs -o jsonpath='{.data.root_ca\.crt}' > step-ca-root.crt
```

Step CA is cluster-internal; it has no Ingress and does not depend on a certificate issued by itself. Use `kubectl port-forward` if you need to access it from outside the cluster.

## Authentik administrator

On a new deployment, visit <https://authentik.myorg.local/if/flow/initial-setup/> and complete the setup flow. For local recovery of the default `akadmin` account:

```sh
kubectl -n trust-plane exec deployment/authentik-server -- ak create_recovery_key 10 akadmin
```

Treat the printed recovery URL as a secret.

## OpenBao initialization and unsealing

OpenBao starts uninitialized. Initialize it once after the pod is running:

```sh
kubectl -n trust-plane exec -it openbao-0 -- bao operator init -key-shares=5 -key-threshold=3
```

Securely store the generated unseal keys and root token outside Git. To unseal, run the following command three times, entering a different saved key each time:

```sh
kubectl -n trust-plane exec -it openbao-0 -- bao operator unseal
```

OpenBao seals after a pod restart; unseal it again, but do not initialize it again. Never delete its PVC unless you intend to destroy its data.

## Argo CD access

Argo CD's ingress certificate is also issued by the Step CA `StepClusterIssuer`. For local recovery if ingress is unavailable:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

The initial admin password is available with:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Log in as `admin` and change it.

## Repository layout

- `argocd/root-application.yaml` — app-of-apps entry point.
- `applications/` — individual child Application manifests with wave annotations.
- `components/*/values.yaml` — Helm chart values.
- `manifests/namespace/` — namespace resources.
- `manifests/pki/` — certificate resources issued by Step CA.
- `manifests/ingress/` — Authentik/OpenBao Ingresses using cert-manager-managed TLS Secrets.
- `manifests/argocd/` — Argo CD local access configuration and Ingress.
- `scripts/bootstrap-step-issuer.sh` — local, repeatable Step CA issuer bootstrap.
- `scripts/bootstrap-argocd.sh` — installs Argo CD and applies the root Application.

Chart versions are pinned in the child Application manifests. Review and update versions intentionally, validating chart values against the selected versions.
