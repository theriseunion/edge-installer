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

  # 创建 observability-system 命名空间
  kubectl create namespace observability-system --dry-run=client -o yaml | kubectl apply -f -

  # 先部署 Prometheus 等基础监控组件
  helm upgrade --install monitoring ./edge-monitoring \
    --namespace observability-system \
    --wait || {
      echo "警告：基础监控套件部署失败"
    }

  # 部署 monitoring-service (提供监控 API)
  echo "部署 monitoring-service..."
  helm upgrade --install monitoring-service ./monitoring-service \
    --namespace observability-system \
    --wait || {
      echo "警告：monitoring-service 部署失败"
    }

  if [ $? -eq 0 ]; then
    echo "✅ 完整监控环境部署成功"
  else
    echo "⚠️  监控套件部署有问题，但核心组件已正常部署"
    echo "你可以稍后手动安装监控套件："
    echo "  ENABLE_MONITORING=true ./deploy.sh"
  fi
fi

echo "部署完成！"
echo "查看 Pod 状态："
kubectl get pods -n $NAMESPACE

if [ "$ENABLE_MONITORING" = "true" ]; then
  echo ""
  echo "监控服务访问方式："
  echo "- Prometheus: kubectl port-forward svc/edge-prometheus 9090:9090 -n observability-system"
  echo "- Grafana: kubectl port-forward svc/edge-grafana 3000:3000 -n observability-system (admin/admin123)"
  echo "- AlertManager: kubectl port-forward svc/edge-alertmanager 9093:9093 -n observability-system"
  echo "- Monitoring API: 通过 apiserver 的 /oapis/monitoring.theriseunion.io/v1alpha1/* 访问"
  echo ""
  echo "检查监控服务状态："
  echo "kubectl get pods -n observability-system"
  echo "kubectl get reverseproxy -n observability-system monitoring-service-proxy"
fi