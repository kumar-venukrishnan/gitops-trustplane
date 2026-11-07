# PAM and Platform Security PoC Plan

This document records the intended scope and staged use cases for the current local Kubernetes PoC. It is a planning document; the use cases below are not necessarily implemented just because the components are deployed.

## PoC components and responsibilities

| Component | Role in this PoC | What it does not provide by itself |
|---|---|---|
| **Kubernetes** | Runs the platform services and test workloads. Kubernetes RBAC can constrain access to cluster resources. | A complete employee access gateway, approval workflow, or session recording. |
| **Authentik** | Identity provider for user sign-in, groups, SSO, and MFA where an application is integrated with it. | Enforcement in applications that have not been integrated or configured to trust it. |
| **OpenBao** | Secrets management, policy-based secret access, token lifecycle, audit devices, and supported dynamic-secret engines when configured. | Automatic rotation or temporary credentials for every external system without configuring the corresponding auth method, engine, and integration. |
| **Step CA** | Private PKI for issuing and managing certificates for configured workloads or users. | A complete PAM gateway, SSH session broker, or session recorder. |

Argo CD manages deployment from Git; it is the GitOps controller, not an identity or PAM control. Ingress provides HTTP(S) routing to applications and is not an access-control substitute.

## Intended outcomes

Use this PoC to learn and demonstrate:

- centralized sign-in and MFA for integrated services;
- least-privilege authorization and explicit denial of unauthorized access;
- bounded token and credential lifetimes;
- internal service certificate issuance and lifecycle;
- audit-event collection and review.

This setup does **not** currently provide a complete PAM capability set. In particular, it does not automatically broker SSH access to bare-metal hosts, record terminal sessions, provide approval workflows, or prevent users from bypassing a gateway. Do not use it as the sole control for production privileged access or as evidence of compliance without implementing and validating the required controls.

## Six PoC use cases

### 1. SSO and MFA for administrative applications

**Goal:** Authenticate users centrally and require MFA for privileged application access.

**Build later:** Configure Authentik users/groups and MFA; integrate an application such as OpenBao using a supported OIDC flow; map claims or groups to application roles.

**Verify:** A test user signs in through Authentik; privileged access requires the configured MFA; an unassigned user cannot access the protected application. Keep a documented recovery/admin path.

### 2. Least-privilege OpenBao secret access

**Goal:** Prove that identities can access only the secrets required for their role or workload.

**Build later:** Configure an OpenBao auth method, create isolated test secret paths, and write policies granting narrow read or write capabilities. Use separate test identities for allowed and denied cases.

**Verify:** The authorized identity can read only its permitted path; requests to unrelated paths are denied; access events are captured by OpenBao audit logging.

### 3. Short-lived OpenBao tokens

**Goal:** Demonstrate time-bounded access to OpenBao rather than relying on long-lived tokens.

**Build later:** Configure the chosen OpenBao authentication method and token policies with appropriate TTL and maximum TTL. Avoid embedding privileged tokens in Git or application images.

**Verify:** A newly issued token has the expected bounded lifetime, can perform only permitted actions, and is rejected after expiry or revocation.

**Scope note:** This limits the OpenBao token. It does not automatically make Kubernetes, SSH, or other credentials short-lived.

### 4. Dynamic credentials for a disposable database

**Goal:** Replace a static test database password with credentials generated for a limited period.

**Build later:** Deploy a disposable database, configure the relevant OpenBao database secrets engine and database role, and grant access only to a test identity or workload.

**Verify:** OpenBao issues credentials that work against the test database, expire or are revoked as configured, and cannot be used for unrelated database roles.

**Safety:** Use only disposable test data and a non-production database during the PoC.

### 5. Internal TLS certificates with Step CA

**Goal:** Issue and operate a certificate for a test internal service.

**Build later:** Configure a Step CA provisioner and trust distribution for the test client; issue a certificate for a test service; configure that service to serve TLS. Document renewal and revocation procedures.

**Verify:** A trusted client validates the certificate and hostname; an expired, untrusted, or revoked certificate is rejected as expected; renewal is demonstrated.

**Scope note:** This demonstrates service identity and PKI lifecycle, not human privileged-session control.

### 6. Kubernetes access using identity and RBAC

**Goal:** Explore identity-based, least-privilege Kubernetes access instead of distributing shared administrator kubeconfigs.

**Build later:** Determine whether the Kubernetes distribution supports configuring API-server OIDC authentication with the chosen identity provider. Configure identity/group claims and Kubernetes RBAC for a narrowly scoped role, such as read-only access to one test namespace. If the local Docker Desktop cluster cannot support the required API-server configuration, use a suitable test cluster or record this as a platform limitation.

**Verify:** The test identity can perform only the allowed actions in the intended namespace and is denied access to other namespaces and privileged operations. Confirm how credentials expire and how access is revoked.

**Scope note:** Kubernetes OIDC login is not guaranteed by deploying Authentik alone. Kubernetes API-server configuration and compatible token/claim handling are required.

## Suggested implementation order

1. Replace PoC placeholder secrets and establish a safe backup/recovery approach before exposing services.
2. Configure Authentik identity, groups, and MFA; then integrate one application (use case 1).
3. Configure OpenBao authentication, narrow policies, and audit logging (use cases 2 and 3).
4. Add a disposable database and test dynamic credentials (use case 4).
5. Configure Step CA and a test TLS workload (use case 5).
6. Evaluate Kubernetes OIDC and RBAC support in the chosen cluster (use case 6).

For every use case, record the configuration, the positive test, the denied/expiry test, where audit evidence is stored, and any limitations. Keep test users and workloads separate from production identities and data.
