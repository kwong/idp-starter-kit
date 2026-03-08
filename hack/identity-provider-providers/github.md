# GitHub / GitHub Enterprise Actions OIDC Setup
# -----------------------------------------------------------------------------
# You can use GitHub as your identity provider if your platform engineers and
# developers are managed via GitHub Teams.
#
# GitHub's OIDC implementation is primarily geared towards Actions, but can be
# used for generic SSO.
#
# 1. Update platform-values.yaml:
#    identity-provider:
#      mode: external
#      issuer_url: "https://token.actions.githubusercontent.com"
#      groups_claim: "teams"  # <--- Important! GitHub uses 'teams' not 'groups'
#
# 2. Create the OIDC Clients (OAuth Apps) in GitHub:
#    - For ArgoCD:
#      - Callback URL: https://argocd.<your-domain>/auth/callback
#      - Put the Client ID in platform-values.yaml -> clients.argocd.client_id
#      - Put the Client Secret in Vault:
#        vault kv put secret/identity-provider/argocd client_secret="<secret>"
#
#    - For Grafana:
#      - Callback URL: https://grafana.<your-domain>/login/generic_oauth
#      - Put the Client Secret in Vault:
#        vault kv put secret/identity-provider/grafana client_secret="<secret>"
