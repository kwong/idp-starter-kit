#!/bin/bash
set -eo pipefail

echo "==> Bootstrapping IDP Starter Kit Local Cluster"

# 1. Spin up the Kind Cluster
if ! kind get clusters | grep -q "^idp$"; then
  echo "--> Creating kind cluster 'idp'..."
  kind create cluster --name idp --config hack/kind-config.yaml
else
  echo "--> Kind cluster 'idp' already exists."
fi

# 2. Install NGINX Ingress Controller
echo "--> Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
echo "--> Waiting for NGINX Ingress to become ready..."
sleep 15
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 3. Install Core ArgoCD
echo "--> Installing ArgoCD Core Components..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side=true --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. Patch ArgoCD Server to run over HTTP (for local testing via Ingress)
echo "--> Patching ArgoCD for local Ingress..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type=merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd

echo "--> Waiting for ArgoCD to become ready..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=120s

# 5. Phase 0: Local Vault Bootstrap
echo "--> Phase 0: Deploying Vault for local dev token extraction..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm dependency update platform/vault 2>/dev/null || true
helm upgrade --install vault platform/vault -n vault --create-namespace -f platform/vault/values.yaml

echo "--> Waiting for Vault to be ready..."
kubectl wait --namespace vault \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=vault \
  --timeout=120s

echo "--> Extracting ephemeral Vault root token from pod logs..."
export VAULT_TOKEN=$(kubectl logs -n vault -l app.kubernetes.io/name=vault | grep 'Root Token:' | head -n 1 | awk '{print $3}')
if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: Could not retrieve dev root token. Is Vault in dev mode?"
  exit 1
fi
echo "Dev Root Token retrieved successfully."

export VAULT_ADDR="http://127.0.0.1:8200"
echo "--> Port-forwarding Vault locally on 8200..."
kubectl port-forward -n vault svc/vault 8200:8200 >/dev/null 2>&1 &
PF_PID=$!
sleep 5

# Seed the OIDC secrets locally via the helper script
chmod +x hack/seed-vault-secrets.sh
./hack/seed-vault-secrets.sh

# Kill the port-forward
kill $PF_PID

# 6. Apply the Root App of Apps
echo "--> Applying Root GitOps Application..."
# Create the apps directory if it doesn't exist
mkdir -p apps
# We will apply apps/platform-core.yaml here 
# kubectl apply -f apps/platform-core.yaml

echo ""
echo "==> Bootstrap Complete!"
echo "ArgoCD will begin synchronising components once apps/platform-core.yaml is created."
