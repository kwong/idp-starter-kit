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

# 5. Apply the Root App of Apps
echo "--> Applying Root GitOps Application..."
# Create the apps directory if it doesn't exist
mkdir -p apps
# We will apply apps/platform-core.yaml here 
# kubectl apply -f apps/platform-core.yaml

echo ""
echo "==> Bootstrap Complete!"
echo "ArgoCD will begin synchronising components once apps/platform-core.yaml is created."
