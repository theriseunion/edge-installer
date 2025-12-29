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
TAG ?= main-qzl-v0.2-arm64 
CHARTS_OUTPUT := bin/_output
CHARTS_SOURCE := .

# List of charts to package - modify this when adding/removing charts
# Note: monitoring-service is embedded in edge-monitoring chart
CHARTS := edge-apiserver edge-console edge-controller edge-monitoring kubeedge vcluster yurt-manager yurthub vast vcluster-k8s-addition yurt-iot-dock

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

# 应用vast CRDs
.PHONY: apply-vast-crds
apply-vast-crds: ## Apply VAST CRDs manually (required before upgrade)
	@echo "Applying VAST CRDs..."
	@kubectl apply -f vast/charts/controller/crds/ || true
	@echo "Waiting for CRDs to be established..."
	@kubectl wait --for condition=established --timeout=60s \
		crds/computetemplates.device.theriseunion.io \
		crds/nodeconfigs.device.theriseunion.io \
		crds/devicemodels.device.theriseunion.io \
		crds/resourcepools.device.theriseunion.io \
		crds/resourcepoolitems.device.theriseunion.io \
		crds/globalconfigs.device.theriseunion.io \
		crds/repositories.registry.theriseunion.io \
		crds/registries.registry.theriseunion.io \
		crds/clusterrepositories.registry.theriseunion.io \
		crds/clusterregistries.registry.theriseunion.io \
		2>/dev/null || echo "Some CRDs may not exist yet, continuing..."

# 部署vast
.PHONY: install-vast
install-vast: ## Install VAST platform
	@echo "Creating namespaces if they don't exist..."
	@kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f - || true
	@kubectl create namespace rise-vast-system --dry-run=client -o yaml | kubectl apply -f - || true
	@echo "Installing VAST platform..."
	helm upgrade --install vast ./vast -n rise-vast-system --create-namespace --debug

# 卸载vast
.PHONY: uninstall-vast
uninstall-vast: uninstall-cert-manager ## Uninstall VAST platform and clean up hook resources
	@echo "Uninstalling VAST platform..."
	@echo "  - Step 1: Deleting webhook configurations (to avoid blocking deletion)..."
	@kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/instance=vast --ignore-not-found=true || true
	@kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/instance=vast --ignore-not-found=true || true
	@kubectl delete mutatingwebhookconfigurations -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@kubectl delete validatingwebhookconfigurations -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true || true
	@echo "  - Step 2: Force deleting all Pods (to avoid hanging on termination)..."
	@kubectl get pods -n rise-vast-system -l app.kubernetes.io/instance=vast --no-headers 2>/dev/null | awk '{print $$1}' | while read pod; do \
		echo "    Removing finalizers from pod: $$pod"; \
		kubectl patch pod "$$pod" -n rise-vast-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true; \
	done || true
	@kubectl delete pods -n rise-vast-system -l app.kubernetes.io/instance=vast --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete pods -n rise-vast-system -l "app.kubernetes.io/name=hami" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@echo "  - Step 3: Deleting Deployments and StatefulSets..."
	@kubectl delete deployment,statefulset -n rise-vast-system -l app.kubernetes.io/instance=vast --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete deployment,statefulset -n rise-vast-system -l "app.kubernetes.io/name=hami" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@echo "  - Step 4: Deleting hook Jobs..."
	@kubectl delete jobs -n rise-vast-system -l app.kubernetes.io/instance=vast --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete jobs -n rise-vast-system -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete jobs -n default -l app.kubernetes.io/instance=vast --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete jobs -n default -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@echo "  - Step 5: Uninstalling Helm release (no wait, returns immediately)..."
	@helm uninstall vast -n rise-vast-system 2>/dev/null || echo "    Helm release not found or already deleted"
	@echo "  - Step 6: Deleting cert-manager resources (Certificates, ClusterIssuers)..."
	@kubectl delete certificates -n rise-vast-system --all --ignore-not-found=true 2>/dev/null || true
	@kubectl delete clusterissuers --all --ignore-not-found=true 2>/dev/null || true
	@kubectl delete certificaterequests -n rise-vast-system --all --ignore-not-found=true 2>/dev/null || true
	@echo "  - Step 7: Deleting certificate secrets and other secrets..."
	@kubectl delete secret -n rise-vast-system apiserver-cert controller-webhook-cert --ignore-not-found=true 2>/dev/null || true
	@kubectl delete secret -n rise-vast-system -l "app.kubernetes.io/instance=vast" --ignore-not-found=true 2>/dev/null || true
	@echo "  - Step 8: Final cleanup of remaining resources..."
	@kubectl delete pods -n rise-vast-system -l app.kubernetes.io/instance=vast --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete serviceaccount,role,rolebinding,configmap,secret -n rise-vast-system -l "app.kubernetes.io/instance=vast" --ignore-not-found=true 2>/dev/null || true
	@kubectl delete clusterrole,clusterrolebinding -l "app.kubernetes.io/instance=vast" --ignore-not-found=true 2>/dev/null || true
	@kubectl delete serviceaccount,role,rolebinding,configmap -n rise-vast-system -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true 2>/dev/null || true
	@kubectl delete clusterrole,clusterrolebinding -l "app.kubernetes.io/name=hami,app.kubernetes.io/component=admission-webhook" --ignore-not-found=true 2>/dev/null || true
	@kubectl delete configmap,secret -n rise-vast-system -l "app.kubernetes.io/name=hami" --ignore-not-found=true 2>/dev/null || true
	@echo "  - Step 9: Deleting remaining HAMI resources..."
	@kubectl delete configmap -n rise-vast-system flavors-cm resource-pools-cm --ignore-not-found=true 2>/dev/null || true
	@kubectl delete secret -n rise-vast-system hami-scheduler-tls --ignore-not-found=true 2>/dev/null || true
	@echo "VAST platform uninstalled and cleaned up"

# 部署 cert-manager
.PHONY: install-cert-manager
install-cert-manager: ## Install cert-manager component
	helm install cert-manager ./vast/charts/cert-manager -n cert-manager --create-namespace \
		--set crds.enabled=true

# 卸载 cert-manager
.PHONY: uninstall-cert-manager
uninstall-cert-manager: ## Uninstall cert-manager component and clean up resources
	@echo "Uninstalling cert-manager..."
	@echo "  - Step 1: Deleting webhook configurations (to avoid blocking deletion)..."
	@kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/name=cert-manager --ignore-not-found=true || true
	@kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/name=cert-manager --ignore-not-found=true || true
	@kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/instance=cert-manager --ignore-not-found=true || true
	@kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/instance=cert-manager --ignore-not-found=true || true
	@echo "  - Step 2: Force deleting all Pods and Jobs..."
	@kubectl get pods -n cert-manager --no-headers 2>/dev/null | awk '{print $$1}' | while read pod; do \
		echo "    Removing finalizers from pod: $$pod"; \
		kubectl patch pod "$$pod" -n cert-manager -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true; \
	done || true
	@kubectl delete pods -n cert-manager --all --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete jobs -n cert-manager --all --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete jobs -n cert-manager -l app.kubernetes.io/instance=cert-manager --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete jobs -n cert-manager -l app.kubernetes.io/name=cert-manager --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@echo "  - Step 3: Deleting Deployments and StatefulSets..."
	@kubectl delete deployment,statefulset -n cert-manager --all --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete deployment,statefulset -n cert-manager -l app.kubernetes.io/instance=cert-manager --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@echo "  - Step 4: Uninstalling Helm release (no wait, returns immediately)..."
	@helm uninstall cert-manager -n cert-manager 2>/dev/null || echo "    Helm release not found or already deleted"
	@echo "  - Step 5: Cleaning up remaining resources in namespace..."
	@kubectl delete all --all -n cert-manager --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
	@kubectl delete serviceaccount,role,rolebinding,configmap,secret -n cert-manager --all --ignore-not-found=true 2>/dev/null || true
	@echo "  - Step 6: Deleting CRDs (using label selector)..."
	@kubectl delete crd -l app.kubernetes.io/name=cert-manager --ignore-not-found=true || true
	@echo "  - Step 7: Deleting CRDs (fallback for unlabeled CRDs)..."
	@kubectl delete crd certificates.cert-manager.io certificaterequests.cert-manager.io \
		issuers.cert-manager.io clusterissuers.cert-manager.io \
		challenges.acme.cert-manager.io orders.acme.cert-manager.io \
		--ignore-not-found=true || true
	@echo "  - Step 8: Deleting cluster-level resources..."
	@kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=cert-manager --ignore-not-found=true || true
	@kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/instance=cert-manager --ignore-not-found=true || true
	@echo "  - Step 9: Deleting namespace..."
	@if kubectl get namespace cert-manager 2>/dev/null | grep -q cert-manager; then \
		echo "    Removing finalizers from namespace cert-manager..."; \
		kubectl patch namespace cert-manager -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true; \
		kubectl delete namespace cert-manager --ignore-not-found=true --force --grace-period=0 2>/dev/null || true; \
	fi || true
	@echo "cert-manager uninstalled and cleaned up"
