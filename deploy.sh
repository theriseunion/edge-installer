#!/bin/bash

# Edge 快速部署脚本
# 使用 Helm 直接部署三个组件

NAMESPACE=${NAMESPACE:-edge-system}
KUBECONFIG_PATH=${KUBECONFIG_PATH:-~/.kube/116.63.161.198.config}
REGISTRY=${REGISTRY:-quanzhenglong.com/edge}
TAG=${TAG:-main}
PULL_POLICY=${PULL_POLICY:-Always}
ENABLE_MONITORING=${ENABLE_MONITORING:-false}
INSTALL_OPENYURT=${INSTALL_OPENYURT:-false}
OPENYURT_API_SERVER=${OPENYURT_API_SERVER:-""}

# 设置 kubeconfig
export KUBECONFIG=$KUBECONFIG_PATH

# 创建命名空间
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 可选安装 OpenYurt
if [ "$INSTALL_OPENYURT" = "true" ]; then
  echo "==================== 安装 OpenYurt ===================="

  # 检查 API Server 地址是否设置
  if [ -z "$OPENYURT_API_SERVER" ]; then
    echo "❌ 错误：必须设置 OPENYURT_API_SERVER 环境变量"
    echo "示例：export OPENYURT_API_SERVER=https://192.168.1.102:6443"
    exit 1
  fi

  echo "OpenYurt API Server: $OPENYURT_API_SERVER"

  # OpenYurt 版本
  OPENYURT_VERSION=${OPENYURT_VERSION:-v1.6.0}
  INSTALL_RAVEN=${INSTALL_RAVEN:-false}

  # 添加 OpenYurt Helm 仓库
  echo "添加 OpenYurt Helm 仓库..."
  helm repo add openyurt https://openyurtio.github.io/openyurt-helm
  helm repo update

  # 1. 安装 yurt-manager (OpenYurt 控制器)
  echo "安装 yurt-manager..."
  helm upgrade --install yurt-manager openyurt/yurt-manager \
    --namespace kube-system \
    --values ./openyurt-1.6/yurt-manager-values.yaml \
    --set image.tag=$OPENYURT_VERSION \
    --wait \
    --timeout 5m || {
      echo "⚠️  yurt-manager 安装失败"
      exit 1
    }

  # 2. 安装 yurt-hub (边缘节点组件配置)
  echo "安装 yurt-hub..."
  helm upgrade --install yurthub openyurt/yurthub \
    --namespace kube-system \
    --values ./openyurt-1.6/yurthub-values.yaml \
    --set kubernetesServerAddr=$OPENYURT_API_SERVER \
    --set image.tag=$OPENYURT_VERSION \
    --wait \
    --timeout 5m || {
      echo "⚠️  yurthub 安装失败"
      exit 1
    }

  # 3. 可选安装 raven-agent (边缘网络通信)
  if [ "$INSTALL_RAVEN" = "true" ]; then
    echo "安装 raven-agent..."
    helm upgrade --install raven-agent openyurt/raven-agent \
      --namespace kube-system \
      --values ./openyurt-1.6/raven-agent-values.yaml \
      --wait \
      --timeout 5m || {
        echo "⚠️  raven-agent 安装失败（非关键组件，继续执行）"
      }
  fi

  echo "✅ OpenYurt 安装成功"
  echo "验证 OpenYurt 组件："
  kubectl get pods -n kube-system | grep yurt

  # 验证关键配置
  echo ""
  echo "验证 yurt-hub 配置..."
  if kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml | grep -q "hub-cert-organizations=system:nodes"; then
    echo "✅ yurt-hub 配置包含 hub-cert-organizations 参数"
  else
    echo "⚠️  yurt-hub 配置缺少 hub-cert-organizations 参数"
  fi
  echo ""
fi

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
  echo "部署监控套件 (Prometheus + Grafana + AlertManager + Monitoring Service)..."

  # 创建 observability-system 命名空间
  kubectl create namespace observability-system --dry-run=client -o yaml | kubectl apply -f -

  # 部署完整监控套件（包含 monitoring-service）
  helm upgrade --install edge-monitoring ./edge-monitoring \
    --namespace observability-system \
    --create-namespace \
    --wait \
    --timeout 10m || {
      echo "⚠️  监控套件部署失败"
      echo "你可以稍后手动安装监控套件："
      echo "  ENABLE_MONITORING=true ./deploy.sh"
      exit 1
    }

  echo "✅ 完整监控环境部署成功"
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
  echo "- Monitoring Service API: kubectl port-forward svc/monitoring-service 8080:80 -n observability-system"
  echo "- 前端监控 API: 通过 apiserver 的 /oapis/monitoring.theriseunion.io/v1alpha1/* 访问"
  echo ""
  echo "检查监控服务状态："
  echo "kubectl get pods -n observability-system"
  echo "kubectl get svc -n observability-system"
fi
