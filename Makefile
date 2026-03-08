.PHONY: help cluster bootstrap up proxy clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

cluster: ## Create the local kind cluster and install Ingress
	@echo "Creating local kind cluster..."
	@bash hack/setup.sh

bootstrap: ## Apply the root ArgoCD application to start GitOps
	@echo "Applying Root GitOps Application..."
	@kubectl apply -f apps/platform-core.yaml

up: cluster bootstrap ## Spin up everything (cluster + GitOps bootstrap)
	@echo "Started the complete setup process."

run: up ## Alias for 'up'

proxy: ## Port-forward ArgoCD UI to localhost:8080
	@echo "Port-forwarding ArgoCD. Username is 'admin'. Get password via: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
	@kubectl port-forward svc/argocd-server -n argocd 8080:80

clean: ## Destroy the local kind cluster
	@echo "Destroying local kind cluster..."
	@kind delete cluster --name idp
