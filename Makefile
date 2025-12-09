
# 默认参数设置
NAMESPACE ?= edge-system
KUBECONFIG ?= $(HOME)/.kube/config
REGISTRY ?= quanzhenglong.com/edge
TAG ?= latest
CONTROLLER_APISERVER_TAG ?= vast-v0.1.0-04
PULL_POLICY ?= Always
ENABLE_MONITORING ?= false
INSTALL_OPENYURT ?= false
OPENYURT_API_SERVER ?=
CERT_MANAGER_VERSION ?= 1.14.4

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