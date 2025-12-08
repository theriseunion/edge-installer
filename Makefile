
NAMESPACE ?= edge-system

# 卸载 Edge Platform
# kubectl get ns edge-system -o json | jq '.spec.finalizers=[]' | kubectl replace --raw /api/v1/namespaces/edge-system/finalize -f -
undeploy:
	@echo "卸载 Edge Platform..."
	@helm uninstall apiserver -n $(NAMESPACE) || true
	@helm uninstall controller -n $(NAMESPACE) || true
	@helm uninstall console -n $(NAMESPACE) || true
	@kubectl delete namespace $(NAMESPACE) || true
	@echo "✅ Edge Platform 卸载成功"