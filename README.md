# GitOps trust plane (local PoC)

A Docker Desktop Kubernetes PoC managed by Argo CD for ingress-nginx, Step CA, cert-manager, Authentik, and OpenBao. Existing Helm chart versions and application values are retained; the child Applications are split into files and ordered by sync wave.

> PoC only, not production-hardened. Replace example application credentials in the values files before use. Protect OpenBao initialization keys and Step CA private material.

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

Applications are organized by Argo CD sync wave:

| Wave | Components |
| --- | --- |
| 0 | `trust-plane` namespace |
| 1 | ingress-nginx |
| 2 | Step CA |
| 3 | cert-manager and the Smallstep Step Issuer controller/CRDs |
| 4 | Step CA-backed Certificate resources |
| 5 | Authentik and OpenBao |
| 6 | Authentik, OpenBao, and Argo CD Ingresses |

Once Step CA has completed its first bootstrap and the Step Issuer controller is installed, run the local credential bootstrap:

```sh
./scripts/bootstrap-step-issuer.sh
```

The script reads Step CA's generated root certificate and provisioner password from the cluster, creates a dedicated Kubernetes Secret for the issuer password, and applies a `StepClusterIssuer` with the matching CA bundle and provisioner key ID. The password is not printed or committed. It is expected to be run locally with a `kubectl` context that can administer the cluster. If the resources are not ready yet, the script waits for them and can be run again safely.

The issuer and password Secret are intentionally bootstrapped locally because Step CA generates its root and provisioner credentials during its initial bootstrap. The Certificate resources in Git reference that issuer and cause cert-manager to create the TLS Secrets; do not create the workload TLS Secrets manually.

Add local host mappings for the UIs:

```text
127.0.0.1 argocd.myorg.local authentik.myorg.local openbao.myorg.local
```

Trust the Step CA root certificate on your computer to avoid browser certificate warnings. Retrieve the public root certificate with:

```sh
kubectl -n trust-plane get configmap step-ca-step-certificates-certs -o jsonpath='{.data.root_ca\.crt}' > step-ca-root.crt
```

Step CA is kept cluster-internal; it does not depend on an Ingress or a certificate issued by itself.

## Authentik administrator

On a new deployment, visit `https://authentik.myorg.local/if/flow/initial-setup/` and complete the setup flow. For local recovery of the default `akadmin` account:

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

The Argo CD ingress certificate is issued into the `argocd` namespace by the same `StepClusterIssuer`. For local recovery if ingress is unavailable:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

The initial admin password is available with:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Log in as `admin` and change it.

## Layout

- `argocd/root-application.yaml` — app-of-apps entry point.
- `applications/` — individual child Application manifests with wave annotations.
- `components/*/values.yaml` — pinned Helm chart settings.
- `manifests/namespace/` — namespace resources.
- `manifests/pki/` — certificate resources issued by Step CA.
- `manifests/ingress/` — workload Ingresses using cert-manager-managed TLS Secrets.
- `scripts/bootstrap-step-issuer.sh` — local, repeatable Step CA issuer bootstrap.

Chart versions are pinned in child Application manifests. Review and update versions intentionally, validating chart values against the selected versions.
