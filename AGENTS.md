# IDP Starter Kit Architecture & Design

This document outlines the architecture, directory structure, and testing approach for the IDP (Internal Developer Platform) Starter Kit. 

The goal of this starter kit is to allow platform engineers to rapidly deploy a production-grade internal developer platform on top of a single Kubernetes cluster, strictly leveraging GitOps methodologies for infrastructure components, robust OIDC integration, Secrets Management, and a unified Control Plane.

## Core Principles

1. **GitOps First:** All platform state is declared in version control. The cluster state strictly matches the Git state via ArgoCD.
2. **Modular Architecture:** Platform components are separated into discrete functional blocks (Apps) allowing teams to easily swap or remove pieces (e.g., swapping Kyverno for Gatekeeper, or Vault for AWS Secrets Manager).
3. **Local-First Development:** The entire IDP can be spun up locally on a developer's machine using `kind` (Kubernetes in Docker) to validate changes before pushing them centrally.
4. **Secure by Default:** Secrets are never hardcoded or pushed to git in plaintext or encoded format. OIDC-driven RBAC is enabled for all platform UI surfaces. Policies enforce secure resource configuration.

## Directory Structure

To maintain a clean separation of concerns, the repository is structured as follows:

```text
idp-starter-kit/
├── AGENTS.md                 # Project architecture and design guidelines
├── Makefile                  # Core orchestrator commands (e.g., make up, make test)
├── apps/                     # ArgoCD Application definitions ("App of Apps")
│   ├── platform-core.yaml    # Bootstraps infrastructure components
│   └── observability.yaml    # Bootstraps metrics/logs/traces components
├── bootstrap/                # Initial cluster-bridging configuration (GitOps ingress rules, repo secrets)
├── hack/                     # Local test scripts, kind-configs, and ad-hoc troubleshooting tooling
│   ├── kind-config.yaml      # Configuration for local Kind cluster
│   └── setup.sh              # Bash orchestration to bootstrap raw resources
└── platform/                 # Core manifest configurations (wrapped Helm charts / Kustomize)
    ├── crossplane/           # Control Plane + Provider configurations
    │   └── apis/             # Crossplane XRDs and Compositions modeling the internal Developer API
    ├── external-secrets/     # ESO and ClusterSecretStore configurations
    ├── keycloak/             # Local OIDC IdP Deployment and baseline Realm Configurations
    ├── kyverno/              # Policy engine and foundational ClusterPolicies
    ├── observability/        # LGTM stack components (Prometheus, Loki, Tempo, Grafana, Otel)
    └── vault/                # Secrets engine backend configurations
```

### Module Organization Patterns

* Every tool inside `platform/` is self-contained. For external Helm charts, we use `kustomization.yaml` files alongside Helm Overrides (`values.yaml`) rather than downloading chart templates locally. 
* ArgoCD `Application` objects (inside `apps/`) point inward to these `platform/` directories.
* Development scripts (`hack/`) act purely as quality-of-life wrappers around standard CLI tools (`kubectl`, `argocd`, `helm`) and are not required for production deployment.

## Test & Development Strategy

Being a complex distributed system of configuration, testing requires multiple levels of verification to ensure the platform remains stable when platform engineers propose changes.

### 1. Local Development Loop (E2E Integration)

The `hack/` directory and `Makefile` form the core local development experience. A developer can stand up a full fresh instance of the IDP:

1. `make cluster`: Provisions the local `kind` cluster with extra port-mappings (80, 443) for realistic Ingress routing.
2. `make bootstrap`: Stages necessary foundational secrets, installs ArgoCD, and creates the root "App of Apps".
3. `make up`: A combined macro invoking the above.

Once running, platform engineers validate changes by altering local git files, pushing to a branch, or pointing their local ArgoCD instance to branch-HEAD, and watching it reconcile the changes.

### 2. Validating Platform APIs (Crossplane)

The core output of this IDP are the developer-facing APIs implemented as Crossplane Compositions. To test these:

1. Platform engineers will author an `API` claim (e.g., `XApp`) in a sample developer namespace.
2. They will observe Crossplane dynamically provisioning the required backend resources (Deployments, Roles, Ingresses).
3. We will enforce that **Kyverno** policy violations block these Compositions if the underlying templates generate invalid or insecure configurations (e.g., a Composition trying to deploy a StatefulSet with root privileges).

### 3. CI/CD Static Verification

While GitOps handles deployment, standard Pull Request checks must still apply:
* **Linting:** Validate all YAML manifests (`yamllint`, `kube-linter`).
* **Dry-Run Testing:** Run `kustomize build` on all components to ensure no cyclic dependencies or syntax errors exist in the patch sets before merging.
### 4. Production Deployment Pathway (EKS/GKE)

While `hack/setup.sh` orchestrates local development on `kind`, deploying this identical IDP payload to production requires an "Infrastructure-as-Code" (IaC) layer (like **Terraform**, **OpenTofu**, or **AWS CDK**) to handle "Day 0" cluster provisioning. 

To bridge this starter kit into production:
1. **Provision the Cluster via IaC**: Use Terraform to stand up the EKS/GKE cluster, VPC, node groups, and necessary cloud IAM OIDC providers (e.g., IRSA for AWS).
2. **IaC Bootstrap of ArgoCD**: Within that same Terraform pipeline, run the `helm` provider to install the base ArgoCD components.
3. **Stage Provider Credentials**: Terraform creates the necessary Kubernetes Secrets (e.g., `aws-creds`) inside the cluster for components like External Secrets Operator or Crossplane to communicate with the host cloud provider.
4. **Deploy the App of Apps**: Terraform applies the root `apps/platform-core.yaml` manifest.

At this point, Terraform is finished. ArgoCD connects to the Git repository, reads the `platform/` manifests, and seamlessly deploys Keycloak, Vault, Crossplane, and the Observability stack in the exact identical configuration as the local `kind` cluster.


# Multi Agent Safety
- When you see unrecognized files just keep going, focus only on files that you recognize.
- When a user asks to push changes to git,, run `git pull --rebase` to integrate latest changes
- Do not switch branches or check out a new/different branch unless the user requests you to.

