# gitops-trustplane

Local Docker Desktop Kubernetes deployment for Authentik, OpenBao, and Smallstep Step CA in the `trust-plane` namespace. Helm installs the applications and ingress-nginx; Kustomize applies the namespace and Ingress resources.

> Local-development baseline for review. It is not production-hardened: replace example credentials, configure backup and recovery, and review chart versions and security settings before broader use.

## Prerequisites

- Docker Desktop Kubernetes enabled
- `kubectl`, Helm 3, and Kustomize installed
- `helm` chart repositories reachable

## Install

From the repository root:

```sh
./scripts/install.sh
```

The script installs the charts from their configured repositories, then applies the Kustomize resources. Chart versions are intentionally not pinned in this initial draft; pin reviewed versions in `scripts/install.sh` before relying on repeatable deployments.

## Local hostnames

Map the following names to `127.0.0.1` in your hosts file (Docker Desktop's LoadBalancer service is reachable locally):

```text
127.0.0.1 authentik.myorg.local openbao.myorg.local step-ca.myorg.local
```

Then use `http://authentik.myorg.local`, `http://openbao.myorg.local`, and `http://step-ca.myorg.local`. For HTTPS, create a TLS Secret named `myorg-local-tls` in `trust-plane` containing a certificate valid for all three hostnames. The Ingress TLS stanzas are ready to reference it.

## Check installation

```sh
kubectl -n trust-plane get pods,svc,ingress
kubectl -n trust-plane get svc
```

Ingress backends assume the chart services are `authentik-server:80`, `openbao:8200`, and `step-ca:9000`. Verify the actual service names and ports from the command above; adjust the Ingress manifests if a chart release changes them.

## Access OpenBao

This local baseline installs OpenBao in standalone mode. Initialize and unseal it after installation; do not store initialization output or unseal keys in Git. See the OpenBao documentation for the current initialization procedure.

## Files

- `scripts/install.sh` — installs the Helm releases and applies Kustomize resources.
- `components/*/values.yaml` — chart values.
- `kustomization.yaml`, `namespace.yaml`, `ingress/` — namespace and ingress resources.
