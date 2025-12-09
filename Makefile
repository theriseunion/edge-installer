
# 默认参数设置
NAMESPACE ?= edge-system
KUBECONFIG ?= $(HOME)/.kube/config
REGISTRY ?= quanzhenglong.com/edge
TAG ?= latest
CONTROLLER_APISERVER_TAG ?= vast-v0.1.0-05
PULL_POLICY ?= Always
ENABLE_MONITORING ?= false
INSTALL_OPENYURT ?= false
OPENYURT_API_SERVER ?=
CERT_MANAGER_VERSION ?= 1.14.4
CERT_MANAGER_INSTALL_YAML ?= https://gh-proxy.net/https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml

.PHONY: deploy
# 部署 Edge Platform
deploy:
	@echo "开始部署 Edge Platform..."
	@NAMESPACE=$(NAMESPACE) \
	 KUBECONFIG=$(KUBECONFIG) \
	 REGISTRY=$(REGISTRY) \
	 TAG=$(TAG) \
	 CONTROLLER_APISERVER_TAG=$(CONTROLLER_APISERVER_TAG) \
	 PULL_POLICY=$(PULL_POLICY) \
	 ENABLE_MONITORING=$(ENABLE_MONITORING) \
	 INSTALL_OPENYURT=$(INSTALL_OPENYURT) \
	 OPENYURT_API_SERVER=$(OPENYURT_API_SERVER) \
	 CERT_MANAGER_VERSION=$(CERT_MANAGER_VERSION) \
	 ./deploy.sh

# 卸载 Edge Platform
# 强制删除名称空间：kubectl get ns edge-system -o json | jq '.spec.finalizers=[]' | kubectl replace --raw /api/v1/namespaces/edge-system/finalize -f -
undeploy:
	@echo "卸载 Edge Platform..."
	@helm uninstall apiserver -n $(NAMESPACE) || true
	@helm uninstall controller -n $(NAMESPACE) || true
	@helm uninstall console -n $(NAMESPACE) || true
	@kubectl delete namespace $(NAMESPACE) || true
	@echo "✅ Edge Platform 卸载成功"

# 卸载 cert-manager
.PHONY: uninstall-cert-manager
uninstall-cert-manager: ## 卸载 cert-manager
	kubectl delete -f $(CERT_MANAGER_INSTALL_YAML) || true
	@echo "✅ cert-manager 卸载成功"