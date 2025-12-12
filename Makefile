# Edge Installer Makefile
# Unified Helm Chart Architecture - Single Command Installation

# CONTAINER_TOOL defines the container tool to be used for building images.
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Chart Packaging

# Registry configuration
REGISTRY ?= quanzhenglong.com/edge
TAG ?= latest
CHARTS_OUTPUT := bin/_output
CHARTS_SOURCE := .

# List of charts to package - modify this when adding/removing charts
# Note: monitoring-service is embedded in edge-monitoring chart
CHARTS := edge-apiserver edge-console edge-controller edge-monitoring kubeedge vcluster yurt-manager yurthub

# ChartMuseum image
MUSEUM_IMG ?= $(REGISTRY)/edge-museum:$(TAG)

.PHONY: package-charts
package-charts: clean-charts ## Package all Helm charts into tgz files (cleans old packages first)
	@echo "Packaging charts from $(CHARTS_SOURCE)..."
	@mkdir -p $(CHARTS_OUTPUT)
	@for chart in $(CHARTS); do \
		echo "Packaging $$chart..."; \
		helm package $(CHARTS_SOURCE)/$$chart -d $(CHARTS_OUTPUT); \
	done
	@# Wait for filesystem to sync after helm package operations
	@# This ensures all chart archives are fully written before listing them
	@sleep 5
	@echo "Charts packaged to $(CHARTS_OUTPUT)/"
	@ls -lh $(CHARTS_OUTPUT)/*.tgz
	

.PHONY: clean-charts
clean-charts: ## Clean packaged charts
	@rm -rf $(CHARTS_OUTPUT)/*.tgz
	@echo "Cleaned packaged charts"

.PHONY: docker-build-museum
docker-build-museum: package-charts ## Build ChartMuseum docker image
	$(CONTAINER_TOOL) build -f Dockerfile.museum -t ${MUSEUM_IMG} .

.PHONY: docker-push-museum
docker-push-museum: ## Push ChartMuseum docker image
	$(CONTAINER_TOOL) push ${MUSEUM_IMG}

.PHONY: docker-buildx-museum
docker-buildx-museum: package-charts ## Build and push ChartMuseum image for cross-platform
	$(CONTAINER_TOOL) buildx build --platform linux/amd64,linux/arm64 -f Dockerfile.museum -t ${MUSEUM_IMG} --push .

##@ Deployment

.PHONY: install-chartmuseum
install-chartmuseum: ## Install ChartMuseum to K8s cluster
	@./scripts/install-chartmuseum.sh

.PHONY: uninstall-chartmuseum
uninstall-chartmuseum: ## Uninstall ChartMuseum from K8s cluster
	@./scripts/uninstall-chartmuseum.sh

##@ Component Management

.PHONY: apply-host-components
apply-host-components: ## Apply Host cluster components
	kubectl apply -f components/host-components.yaml

.PHONY: apply-member-components
apply-member-components: ## Apply Member cluster components
	kubectl apply -f components/member-components.yaml

.PHONY: delete-host-components
delete-host-components: ## Delete Host cluster components
	kubectl delete -f components/host-components.yaml --ignore-not-found=true

##@ Unified Installation

.PHONY: install-all
install-all: ## Install all components (standalone cluster)
	helm install edge-platform ./edge-controller

.PHONY: install-host
install-host: ## Install Host cluster components (with console)
	helm install edge-platform ./edge-controller --set global.mode=host

.PHONY: install-member
install-member: ## Install Member cluster components (without console)
	helm install edge-platform ./edge-controller --set global.mode=member

.PHONY: install-controller-only
install-controller-only: ## Install only controller infrastructure
	helm install edge-platform ./edge-controller --set global.mode=none

.PHONY: upgrade-all
upgrade-all: ## Upgrade all components
	helm upgrade edge-platform ./edge-controller

.PHONY: uninstall
uninstall: ## Uninstall all components
	helm uninstall edge-platform

.PHONY: lint
lint: ## Lint the Helm chart
	helm lint ./edge-controller

.PHONY: template
template: ## Show rendered templates
	helm template edge-platform ./edge-controller

##@ Examples

.PHONY: example-host
example-host: ## Example: Install host cluster with custom registry
	helm install edge-platform ./edge-controller \
		--set global.mode=host \
		--set global.imageRegistry=your-registry.com/edge \
		--set controller.image.tag=v1.0.0

.PHONY: example-member
example-member: ## Example: Install member cluster
	helm install edge-platform ./edge-controller \
		--set global.mode=member \
		--set autoInstall.monitoring.enabled=false

# 部署vas
.PHONY: install-vast
install-vast: ## Install VAST platform
	helm install vast ./vast -n vast-system --create-namespace

# 卸载vast
.PHONY: uninstall-vast
uninstall-vast: ## Uninstall VAST platform and clean up hook resources
	@echo "Uninstalling VAST platform..."
	@helm uninstall vast -n vast-system --wait || true
	@echo "Cleaning up remaining hook resources..."
	@echo "  - Deleting hook Jobs..."
	@kubectl delete jobs -n vast-system -l app.kubernetes.io/instance=vast --ignore-not-found=true || true
	@kubectl delete jobs -n vast-system -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@kubectl delete jobs -n default -l app.kubernetes.io/instance=vast --ignore-not-found=true || true
	@kubectl delete jobs -n default -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@echo "  - Deleting hook Pods..."
	@kubectl delete pods -n vast-system -l app.kubernetes.io/instance=vast --ignore-not-found=true || true
	@kubectl delete pods -n vast-system -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@kubectl delete pods -n default -l app.kubernetes.io/instance=vast --ignore-not-found=true || true
	@kubectl delete pods -n default -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@echo "  - Deleting hook ServiceAccounts, Roles, RoleBindings..."
	@kubectl delete serviceaccount -n vast-system -l "app.kubernetes.io/instance=vast,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@kubectl delete role -n vast-system -l "app.kubernetes.io/instance=vast,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@kubectl delete rolebinding -n vast-system -l "app.kubernetes.io/instance=vast,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@kubectl delete clusterrole -l "app.kubernetes.io/instance=vast,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@kubectl delete clusterrolebinding -l "app.kubernetes.io/instance=vast,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@echo "VAST platform uninstalled and cleaned up"