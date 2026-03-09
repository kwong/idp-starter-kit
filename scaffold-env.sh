#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Environment Scaffolding Script
# ==============================================================================
# This script reads platform-values.yaml as the source of truth to dynamically
# generate the environments/ subfolders and the bootstrap/ App-of-Apps config.

# 1. Dependency Check
if ! command -v yq &> /dev/null; then
    echo "ERROR: 'yq' is not installed."
    echo "Please install it to run this script:"
    echo "  macOS: brew install yq"
    echo "  Ubuntu/Debian: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod a+x /usr/local/bin/yq"
    exit 1
fi

VALUES_FILE="platform-values.yaml"
if [ ! -f "$VALUES_FILE" ]; then
    echo "ERROR: $VALUES_FILE not found in current directory."
    exit 1
fi

# 2. Extract Environments
ENVS=$(yq e '.environments[]?' "$VALUES_FILE")
if [ -z "$ENVS" ]; then
    echo "No environments defined in $VALUES_FILE"
    exit 0
fi

# 3. Process Each Environment
for ENV_NAME in $ENVS; do
    ENV_DIR="environments/$ENV_NAME"
    BOOTSTRAP_FILE="bootstrap/$ENV_NAME.yaml"

    echo "==> Processing environment: $ENV_NAME"

    if [ -d "$ENV_DIR" ]; then
        echo "  INFO: Directory $ENV_DIR already exists."
        echo "        Skipping scaffolding to preserve any custom patches."
        continue
    fi

    # Create directory
    mkdir -p "$ENV_DIR"
    
    # Render Kustomization
    KUSTOMIZATION_FILE="$ENV_DIR/kustomization.yaml"
    cat <<EOF > "$KUSTOMIZATION_FILE"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Scaffolded for environment: $ENV_NAME
resources:
EOF

    # Helper function to append a component if enabled
    add_component() {
        local COMP="$1"
        local ENABLED="$2"
        # For Keycloak, check IdP mode instead of explicit component toggle
        if [ "$COMP" = "keycloak" ]; then
            local IDP_MODE=$(yq e '.identity-provider.mode' "$VALUES_FILE")
            if [ "$IDP_MODE" = "internal" ]; then
                ENABLED="true"
            else
                ENABLED="false"
            fi
        fi

        if [ "$ENABLED" = "true" ]; then
            echo "  - ../../components/$COMP/base" >> "$KUSTOMIZATION_FILE"
            
            # Create a values stub for easy overriding
            if [ "$COMP" != "oidc-configuration" ] && [ "$COMP" != "policies" ]; then
                VALUES_STUB="$ENV_DIR/${COMP}-values.yaml"
                cat <<EOF > "$VALUES_STUB"
# $COMP environment-specific Helm value overrides for $ENV_NAME.
# These patches are applied on top of components/$COMP/base/values.yaml.
# https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/
EOF
            fi
        fi
    }

    # Helper function to get component toggle with default
    get_toggle() {
        local COMP="$1"
        local DEFAULT="$2"
        local VAL
        VAL=$(yq e ".components.${COMP}" "$VALUES_FILE")
        if [ "$VAL" = "null" ]; then
            echo "$DEFAULT"
        else
            echo "$VAL"
        fi
    }

    # Evaluate all possible components
    echo "  Parsing components..."
    
    # Always include core components if defined in schema, or default to true
    add_component "argocd" "$(get_toggle "argocd" "true")"
    add_component "keycloak" "handled_by_function"
    add_component "external-secrets" "$(get_toggle "external-secrets" "true")"
    add_component "oidc-configuration" "$(get_toggle "oidc-configuration" "true")"
    add_component "kyverno" "$(get_toggle "kyverno" "true")"
    add_component "policies" "$(get_toggle "policies" "true")"
    add_component "crossplane" "$(get_toggle "crossplane" "true")"
    add_component "vault" "$(get_toggle "vault" "true")"
    add_component "kube-prometheus-stack" "$(get_toggle "kube-prometheus-stack" "true")"
    add_component "loki" "$(get_toggle "loki" "true")"
    add_component "tempo" "$(get_toggle "tempo" "true")"
    add_component "otel-collector" "$(get_toggle "otel-collector" "true")"

    # 4. Generate Bootstrap ArgoCD Application
    cat <<EOF > "$BOOTSTRAP_FILE"
---
# Bootstrap Application for the '$ENV_NAME' environment.
# Applied once during setup: kubectl apply -f bootstrap/$ENV_NAME.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: idp-$ENV_NAME
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: platform
  source:
    repoURL: 'https://github.com/kwong/idp-starter-kit.git'
    targetRevision: HEAD
    path: environments/$ENV_NAME
    kustomize:
      enableHelm: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

    echo "  Created environments/$ENV_NAME layer and bootstrap/$ENV_NAME.yaml"
    
    # If this is the 'dev' environment, ensure AppProject exists in the bootstrap file
    if [ "$ENV_NAME" = "dev" ] && ! grep -q "kind: AppProject" "$BOOTSTRAP_FILE"; then
        sed -i.bak '1i\
---\
apiVersion: argoproj.io/v1alpha1\
kind: AppProject\
metadata:\
  name: platform\
  namespace: argocd\
spec:\
  description: "Core IDP platform components"\
  sourceRepos:\
    - \x27*\x27\
  destinations:\
    - namespace: \x27*\x27\
      server: https://kubernetes.default.svc\
  clusterResourceWhitelist:\
    - group: \x27*\x27\
      kind: \x27*\x27\
' "$BOOTSTRAP_FILE"
        rm -f "${BOOTSTRAP_FILE}.bak"
    fi

done

echo ""
echo "Scaffolding complete. Commit your changes and push to GitOps!"
