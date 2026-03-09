# Microsoft Entra ID (Azure AD) OIDC Setup
# -----------------------------------------------------------------------------
# You can use Entra ID as your identity provider for the IDP Starter Kit.
# 
# 1. Update platform-values.yaml:
#    identity-provider:
#      mode: external
#      issuer_url: "https://login.microsoftonline.com/<your-tenant-id>/v2.0"
#      groups_claim: "groups"  # Entra uses 'groups'
# 
# 2. In the Azure Portal, create App Registrations for ArgoCD, Grafana, and Vault.
#    - For each app, create a Client Secret and note the Application (client) ID.
#    - Navigate to Token Configuration and add the "groups" optional claim
#      so that group membership is returned in the ID/Access tokens.
# 
# 3. Seed the Client Secrets into Vault using ./seed-vault-secrets.sh:
#    - Vault KV path: secret/identity-provider/grafana
#    - Vault KV path: secret/identity-provider/vault
#    - Vault KV path: secret/identity-provider/argocd (if made confidential)
