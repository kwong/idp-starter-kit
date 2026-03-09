#!/bin/bash
# =============================================================================
# ./seed-vault-secrets.sh
# =============================================================================
# Purpose: Seeds required Identity Provider client secrets into Vault KV during
# the Phase 0 bootstrap. This ensures secrets are available to ESO and the
# Vault init-job before ArgoCD attempts to deploy SSO-aware components.
#
# Usage:
#   For local dev: Run automatically by hack/setup.sh using an ephemeral token.
#   For prod: Run manually or via Terraform after Vault auto-unseals.
#
# Prerequisite: VAULT_ADDR and VAULT_TOKEN must be set in the environment.
# =============================================================================
set -e

echo "==> Phase 0: Seeding Identity Provider secrets into Vault KV"

if [ -z "$VAULT_ADDR" ]; then
  echo "Error: VAULT_ADDR is not set."
  exit 1
fi

if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: VAULT_TOKEN is not set. You must authenticate to Vault first."
  exit 1
fi

# We use the local vault CLI if available, otherwise fallback to kubectl exec
if command -v vault &> /dev/null; then
  VAULT_CMD="vault"
else
  echo "--> Vault CLI not found locally. Falling back to kubectl exec inside Vault pod..."
  VAULT_CMD="kubectl exec -it -n vault vault-0 -- vault"
fi

# Automatically enable kv-v2 if not already enabled
$VAULT_CMD secrets enable -path=secret kv-v2 2>/dev/null || true

# -----------------------------------------------------------------------------
# Grafana OIDC Secret
# -----------------------------------------------------------------------------
if [ -z "$GRAFANA_CLIENT_SECRET" ]; then
  read -s -p "Enter Grafana OIDC Client Secret (or press enter for dummy 'dummy-secret'): " input_secret
  echo ""
  GRAFANA_CLIENT_SECRET=${input_secret:-"dummy-secret"}
fi

echo "--> Seeding Grafana OIDC secret to secret/identity-provider/grafana..."
$VAULT_CMD kv put secret/identity-provider/grafana client_secret="$GRAFANA_CLIENT_SECRET" >/dev/null

# -----------------------------------------------------------------------------
# Vault OIDC Secret
# -----------------------------------------------------------------------------
if [ -z "$VAULT_CLIENT_SECRET" ]; then
  read -s -p "Enter Vault OIDC Client Secret (or press enter for dummy 'dummy-secret'): " input_secret
  echo ""
  VAULT_CLIENT_SECRET=${input_secret:-"dummy-secret"}
fi

echo "--> Seeding Vault OIDC secret to secret/identity-provider/vault..."
$VAULT_CMD kv put secret/identity-provider/vault client_secret="$VAULT_CLIENT_SECRET" >/dev/null

echo "==> Vault KV seeding complete!"
