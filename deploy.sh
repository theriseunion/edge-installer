#!/bin/bash

# Edge 快速部署脚本
# 使用 Helm 直接部署三个组件

NAMESPACE=${NAMESPACE:-edge-system}
KUBECONFIG_PATH=${KUBECONFIG_PATH:-~/.kube/116.63.161.198.config}
REGISTRY=${REGISTRY:-quanzhenglong.com/edge}
TAG=${TAG:-main}
PULL_POLICY=${PULL_POLICY:-Always}
ENABLE_MONITORING=${ENABLE_MONITORING:-false}

# 设置 kubeconfig
export KUBECONFIG=$KUBECONFIG_PATH

# 创建命名空间
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 部署 Controller
helm upgrade --install controller ./edge-controller \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/controller \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait

# 部署 API Server
helm upgrade --install apiserver ./edge-apiserver \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/apiserver \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait

# 部署 Console
helm upgrade --install console ./edge-console \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/console \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --set 'env[0].name=NEXT_PUBLIC_API_BASE_URL' \
  --set 'env[0].value=http://apiserver:8080' \
  --wait

# 可选部署监控套件
if [ "$ENABLE_MONITORING" = "true" ]; then
  echo "部署监控套件 (Prometheus + Grafana + AlertManager)..."
  helm upgrade --install monitoring ./edge-monitoring \
    --namespace $NAMESPACE \
    --wait || {
      echo "警告：监控套件部署失败，但核心组件已正常部署"
      echo "你可以稍后手动安装监控套件："
      echo "  ENABLE_MONITORING=true ./deploy.sh"
    }
fi

echo "部署完成！"
echo "查看 Pod 状态："
kubectl get pods -n $NAMESPACE

if [ "$ENABLE_MONITORING" = "true" ]; then
  echo ""
  echo "监控服务访问方式："
  echo "- Prometheus: kubectl port-forward svc/edge-prometheus 9090:9090 -n $NAMESPACE"
  echo "- Grafana: kubectl port-forward svc/edge-grafana 3000:3000 -n $NAMESPACE (admin/admin123)"
  echo "- AlertManager: kubectl port-forward svc/edge-alertmanager 9093:9093 -n $NAMESPACE"
fi