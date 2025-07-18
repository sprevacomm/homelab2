# Homelab Infrastructure Makefile

.PHONY: help
help: ## Show this help
	@echo "Homelab Infrastructure Management"
	@echo "================================="
	@echo ""
	@echo "Quick Start:"
	@echo "  make install    - Complete installation"
	@echo "  make status     - Check infrastructure status"
	@echo "  make logs       - Tail all infrastructure logs"
	@echo ""
	@echo "All Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: prereq
prereq: ## Run prerequisites check
	@echo "Running prerequisites..."
	@cd infrastructure/docs && ./prerequisites.sh

.PHONY: install
install: prereq ## Full installation
	@echo "Bootstrapping ArgoCD..."
	@cd infrastructure/bootstrap && ./bootstrap.sh
	@echo "Waiting for ArgoCD to be ready..."
	@kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
	@echo "Deploying infrastructure..."
	@kubectl apply -f gitops/bootstrap/infrastructure.yaml

.PHONY: validate
validate: ## Validate all YAML files
	@echo "Validating YAML files..."
	@yamllint -c .yamllint .
	@echo "Validating Kubernetes manifests..."
	@find . -name "*.yaml" -type f | xargs kubeval --ignore-missing-schemas

.PHONY: diff
diff: ## Show ArgoCD diff
	@argocd app diff infrastructure --local gitops/infrastructure

.PHONY: sync
sync: ## Sync all applications
	@argocd app sync infrastructure --prune

.PHONY: status
status: ## Check infrastructure status
	@echo "=== Cluster Nodes ==="
	@kubectl get nodes
	@echo "\n=== ArgoCD Applications ==="
	@kubectl get applications -n argocd
	@echo "\n=== Infrastructure Pods ==="
	@kubectl get pods -n argocd
	@kubectl get pods -n metallb-system
	@kubectl get pods -n traefik
	@kubectl get pods -n monitoring
	@kubectl get pods -n cert-manager
	@kubectl get pods -n velero

.PHONY: logs
logs: ## Tail logs from all infrastructure components
	@stern --all-namespaces -l app.kubernetes.io/part-of=infrastructure

.PHONY: backup
backup: ## Create backup of all applications
	@echo "Creating backup..."
	@kubectl get applications -n argocd -o yaml > backups/applications-$(shell date +%Y%m%d-%H%M%S).yaml
	@kubectl get configmap -n argocd -o yaml > backups/argocd-config-$(shell date +%Y%m%d-%H%M%S).yaml
	@echo "Backup created in backups/"

.PHONY: test-dns
test-dns: ## Test DNS resolution
	@echo "Testing DNS resolution..."
	@for domain in argocd traefik grafana prometheus alertmanager adguard; do \
		echo -n "$$domain.susdomain.name: "; \
		dig +short $$domain.susdomain.name || echo "FAILED"; \
	done

.PHONY: test-ingress
test-ingress: ## Test ingress endpoints
	@echo "Testing ingress endpoints..."
	@for domain in argocd traefik grafana prometheus alertmanager adguard; do \
		echo -n "https://$$domain.susdomain.name: "; \
		curl -sSf -o /dev/null -w "%{http_code}" https://$$domain.susdomain.name || echo "FAILED"; \
		echo ""; \
	done

.PHONY: clean
clean: ## Remove all infrastructure (DANGEROUS!)
	@echo "This will remove all infrastructure. Are you sure? [y/N]"
	@read -r response; \
	if [ "$$response" = "y" ]; then \
		kubectl delete application infrastructure -n argocd; \
		echo "Infrastructure removed"; \
	else \
		echo "Cancelled"; \
	fi