# Image URL to use all building/pushing image targets
IMG ?= quanzhenglong.com/edge/edge-installer:latest

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: fmt vet ## Run tests.
	go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: fmt vet ## Build installer binary.
	go build -o bin/installer cmd/installer/main.go

.PHONY: run
run: fmt vet ## Run installer in operator mode from your host.
	go run ./cmd/installer/main.go --mode=operator

.PHONY: run-install
run-install: fmt vet ## Run installer in install mode.
	go run ./cmd/installer/main.go --mode=install --installation=edge-platform --namespace=edge-system

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
KUSTOMIZE ?= $(LOCALBIN)/kustomize

## Tool Versions
CONTROLLER_TOOLS_VERSION ?= v0.16.5
KUSTOMIZE_VERSION ?= v5.4.3

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	$(call go-install-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen,$(CONTROLLER_TOOLS_VERSION))

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary (ideally with version)
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f $(1) ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
GOBIN=$(LOCALBIN) go install $${package} ;\
mv "$$(echo "$(1)" | sed "s/-$(3)$$//")" $(1) || true ;\
}
endef

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: manifests
manifests: controller-gen ## Generate CRD manifests.
	$(CONTROLLER_GEN) crd paths="./api/..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./api/..."

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy installer to the K8s cluster specified in ~/.kube/config.
	cd config/installer && $(KUSTOMIZE) edit set image installer=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: kustomize ## Undeploy installer from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Image

.PHONY: docker-build
docker-build: ## Build docker image with the installer.
	$(CONTAINER_TOOL) build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the installer.
	$(CONTAINER_TOOL) push ${IMG}

.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for cross-platform support
	$(CONTAINER_TOOL) buildx build --platform linux/amd64,linux/arm64 -t ${IMG} --push .

##@ ChartMuseum

MUSEUM_IMG ?= quanzhenglong.com/edge/edge-museum:latest
CHARTS_OUTPUT := bin/_output
CHARTS_SOURCE := .

.PHONY: package-charts
package-charts: ## Package all Helm charts into tgz files
	@echo "Packaging charts from $(CHARTS_SOURCE)..."
	@mkdir -p $(CHARTS_OUTPUT)
	@for chart in edge-controller edge-apiserver edge-console edge-monitoring; do \
		echo "Packaging $$chart..."; \
		helm package $(CHARTS_SOURCE)/$$chart -d $(CHARTS_OUTPUT); \
	done
	@echo "Charts packaged to $(CHARTS_OUTPUT)/"
	@ls -lh $(CHARTS_OUTPUT)/*.tgz

.PHONY: docker-build-museum
docker-build-museum: package-charts ## Build ChartMuseum docker image
	$(CONTAINER_TOOL) build -f Dockerfile.museum -t ${MUSEUM_IMG} .

.PHONY: docker-push-museum
docker-push-museum: ## Push ChartMuseum docker image
	$(CONTAINER_TOOL) push ${MUSEUM_IMG}

.PHONY: docker-buildx-museum
docker-buildx-museum: package-charts ## Build and push ChartMuseum image for cross-platform
	$(CONTAINER_TOOL) buildx build --platform linux/amd64,linux/arm64 -f Dockerfile.museum -t ${MUSEUM_IMG} --push .
