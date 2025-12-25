#!/bin/bash

# Edge 快速部署脚本
# 使用 Helm 直接部署三个组件

# 默认参数设置
NAMESPACE=${NAMESPACE:-edge-system}
KUBECONFIG_PATH=${KUBECONFIG:-~/.kube/config}
REGISTRY=${REGISTRY:-quanzhenglong.com/edge}
TAG=${TAG:-main-qzl-v0.2}
PULL_POLICY=${PULL_POLICY:-Always}
ENABLE_MONITORING=${ENABLE_MONITORING:-false}
INSTALL_OPENYURT=${INSTALL_OPENYURT:-false}
OPENYURT_API_SERVER=${OPENYURT_API_SERVER:-""}

# 显示所有部署参数
echo "==================== Edge Platform 部署参数确认 ===================="
echo "命名空间 (NAMESPACE):           $NAMESPACE"
echo "Kubeconfig 路径 (KUBECONFIG):   $KUBECONFIG_PATH"
echo "镜像仓库 (REGISTRY):            $REGISTRY"
echo "镜像标签 (TAG):                 $TAG"
echo "拉取策略 (PULL_POLICY):         $PULL_POLICY"
echo "启用监控 (ENABLE_MONITORING):   $ENABLE_MONITORING"
echo "安装 OpenYurt (INSTALL_OPENYURT): $INSTALL_OPENYURT"
if [ "$INSTALL_OPENYURT" = "true" ]; then
    echo "OpenYurt API Server:          $OPENYURT_API_SERVER"
fi
echo "===================================================================="

# 用户确认
echo ""
read -p "确认以上参数并开始部署？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ 用户取消部署"
    exit 1
fi

echo ""
echo "✅ 开始部署 Edge Platform..."
echo ""

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
    echo ""
    echo "快速设置方法："
    echo "  export OPENYURT_API_SERVER=\$(kubectl config view --minify | grep server | awk '{print \$2}')"
    echo ""
    echo "或手动设置："
    echo "  export OPENYURT_API_SERVER=https://192.168.1.102:6443"
    echo ""
    exit 1
  fi

  echo "OpenYurt API Server: $OPENYURT_API_SERVER"

  # 使用本地 OpenYurt 1.6 安装脚本
  echo "使用本地 OpenYurt 1.6 安装脚本..."

  # 设置环境变量并执行本地安装脚本
  export KUBECONFIG=$KUBECONFIG_PATH
  # 不传递 NAMESPACE，让 OpenYurt 使用默认的 kube-system
  # 如需修改，可通过 OPENYURT_NAMESPACE 环境变量设置
  export OPENYURT_API_SERVER=$OPENYURT_API_SERVER
  export OPENYURT_VERSION=${OPENYURT_VERSION:-v1.6.0}
  export INSTALL_RAVEN=${INSTALL_RAVEN:-false}
  export SKIP_HELM_UPDATE=${SKIP_HELM_UPDATE:-true}  # 默认跳过 Helm update，加快安装速度

  # 执行本地安装脚本
  if [ -f "./openyurt-1.6/install.sh" ]; then
    chmod +x ./openyurt-1.6/install.sh
    ./openyurt-1.6/install.sh || {
      echo "⚠️  OpenYurt 安装失败"
      exit 1
    }
  else
    echo "❌ 错误：找不到本地 OpenYurt 安装脚本 ./openyurt-1.6/install.sh"
    exit 1
  fi

  echo "✅ OpenYurt 安装成功"
  echo "验证 OpenYurt 组件："
  kubectl get pods -n kube-system | grep yurt

  # 验证关键配置
  echo ""
  echo "验证 yurt-hub 配置..."
  if kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml 2>/dev/null | grep -q "hub-cert-organizations=system:nodes"; then
    echo "✅ yurt-hub 配置包含 hub-cert-organizations 参数"
  else
    echo "⚠️  yurt-hub 配置缺少 hub-cert-organizations 参数"
  fi
  echo ""
fi


# 部署 API Server
echo "部署 API Server..."
helm upgrade --install apiserver ./edge-apiserver \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/apiserver \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait || {
    echo "❌ API Server 部署失败"
    echo "请检查镜像是否存在以及集群连接状态"
    exit 1
  }

# 部署 Controller
echo "部署 Controller..."
helm upgrade --install controller ./edge-controller \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/controller \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait || {
    echo "❌ Controller 部署失败"
    exit 1
  }

# 部署 Console
echo "部署 Console..."
helm upgrade --install console ./edge-console \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/console \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --set 'env[0].name=NEXT_PUBLIC_API_BASE_URL' \
  --set 'env[0].value=http://apiserver:8080' \
  --wait || {
    echo "❌ Console 部署失败"
    exit 1
  }

# 可选部署监控套件
if [ "$ENABLE_MONITORING" = "true" ]; then
  echo "部署监控套件 (Prometheus + Grafana + AlertManager + Monitoring Service)..."

  # 创建 observability-system 命名空间
  kubectl create namespace observability-system --dry-run=client -o yaml | kubectl apply -f -

  # 部署完整监控套件（包含 monitoring-service）
  helm upgrade --install edge-monitoring ./edge-monitoring \
    --namespace observability-system \
    --create-namespace \
    --set monitoringService.image.tag=$TAG \
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
