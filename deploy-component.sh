#!/bin/bash

# Edge Platform Component-based Installation Script
# 使用 Component CR 驱动的声明式安装流程
# 符合文档: docs-installer/component-installation-flow.md

set -e  # 遇到错误立即退出

# 默认参数设置
NAMESPACE=${NAMESPACE:-edge-system}
KUBECONFIG_PATH=${KUBECONFIG:-~/.kube/config}
REGISTRY=${REGISTRY:-quanzhenglong.com/edge}
TAG=${TAG:-main}
PULL_POLICY=${PULL_POLICY:-Always}
ENABLE_MONITORING=${ENABLE_MONITORING:-false}
CHARTS_PATH=${CHARTS_PATH:-$(pwd)}  # Helm Chart 路径

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}ℹ ${NC}$1"
}

log_warn() {
    echo -e "${YELLOW}⚠ ${NC}$1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# 显示所有部署参数
echo "==================== Edge Platform 部署参数确认 ===================="
echo "命名空间 (NAMESPACE):           $NAMESPACE"
echo "Kubeconfig 路径 (KUBECONFIG):   $KUBECONFIG_PATH"
echo "镜像仓库 (REGISTRY):            $REGISTRY"
echo "镜像标签 (TAG):                 $TAG"
echo "拉取策略 (PULL_POLICY):         $PULL_POLICY"
echo "启用监控 (ENABLE_MONITORING):   $ENABLE_MONITORING"
echo "Helm Charts 路径:               $CHARTS_PATH"
echo "===================================================================="
echo ""

# 用户确认
read -p "确认以上参数并开始部署？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_error "用户取消部署"
    exit 1
fi

echo ""
log_info "开始部署 Edge Platform (Component CR 模式)..."
echo ""

# 设置 kubeconfig
export KUBECONFIG=$KUBECONFIG_PATH

# 创建命名空间
log_info "创建命名空间: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

###########################################
# 步骤 1: 安装 Controller (包含 CRDs)
###########################################
echo ""
log_info "========== 步骤 1/4: 安装 Controller + CRDs =========="
log_info "Helm Chart: edge-controller"
log_info "包含内容: CRDs + Controller Deployment"

helm upgrade --install controller $CHARTS_PATH/edge-controller \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/controller \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait \
  --timeout=5m || {
    log_error "Controller 安装失败"
    exit 1
  }

log_success "Controller 安装成功"

# 等待 Controller Pod Ready
log_info "等待 Controller Pod Ready..."
kubectl wait --for=condition=available deployment/controller \
  -n $NAMESPACE --timeout=120s || {
    log_error "Controller Pod 启动超时"
    log_info "查看 Pod 状态:"
    kubectl get pods -n $NAMESPACE
    log_info "查看 Controller 日志:"
    kubectl logs -n $NAMESPACE deployment/controller --tail=50
    exit 1
  }

log_success "Controller Pod 已就绪"

# 验证 CRDs 安装
log_info "验证 CRDs 安装..."
if kubectl get crd components.ext.theriseunion.io &>/dev/null; then
    log_success "Component CRD 已安装"
else
    log_error "Component CRD 未找到"
    exit 1
fi

###########################################
# 步骤 2: 创建 Component CRs
###########################################
echo ""
log_info "========== 步骤 2/4: 创建 Component CRs =========="

# 创建 APIServer Component
log_info "创建 APIServer Component CR..."
cat <<EOF | kubectl apply -f -
apiVersion: ext.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: edge-apiserver
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: edge-apiserver
    app.kubernetes.io/component: apiserver
    app.kubernetes.io/part-of: edge-platform
spec:
  type: apiserver
  enabled: true
  chart:
    name: edge-apiserver
    namespace: $NAMESPACE
    releaseName: edge-apiserver
  values:
    image:
      repository: $REGISTRY/apiserver
      tag: $TAG
      pullPolicy: $PULL_POLICY
EOF

log_success "APIServer Component CR 已创建"

# 创建 Console Component
log_info "创建 Console Component CR..."
cat <<EOF | kubectl apply -f -
apiVersion: ext.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: edge-console
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: edge-console
    app.kubernetes.io/component: console
    app.kubernetes.io/part-of: edge-platform
spec:
  type: console
  enabled: true
  chart:
    name: edge-console
    namespace: $NAMESPACE
    releaseName: edge-console
  values:
    image:
      repository: $REGISTRY/console
      tag: $TAG
      pullPolicy: $PULL_POLICY
    env:
      - name: NEXT_PUBLIC_API_BASE_URL
        value: http://apiserver:8080
EOF

log_success "Console Component CR 已创建"

# 可选: 创建 Monitoring Component
if [ "$ENABLE_MONITORING" = "true" ]; then
  log_info "创建 Monitoring Component CR..."

  # 创建 observability-system 命名空间
  kubectl create namespace observability-system --dry-run=client -o yaml | kubectl apply -f -

  cat <<EOF | kubectl apply -f -
apiVersion: ext.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: edge-monitoring
  namespace: observability-system
  labels:
    app.kubernetes.io/name: edge-monitoring
    app.kubernetes.io/component: monitoring
    app.kubernetes.io/part-of: edge-platform
spec:
  type: monitoring
  enabled: true
  chart:
    name: edge-monitoring
    namespace: observability-system
    releaseName: edge-monitoring
  values:
    monitoringService:
      image:
        tag: $TAG
EOF

  log_success "Monitoring Component CR 已创建"
fi

###########################################
# 步骤 3: 等待 Component Controller 安装组件
###########################################
echo ""
log_info "========== 步骤 3/4: 等待 Component Controller 安装组件 =========="

# 等待 APIServer Component 安装完成
log_info "等待 APIServer Component 安装完成 (最长 5 分钟)..."
kubectl wait --for=jsonpath='{.status.phase}'=Installed \
  component.ext.theriseunion.io/edge-apiserver -n $NAMESPACE --timeout=300s || {
    log_error "APIServer Component 安装超时"
    log_info "Component 状态:"
    kubectl get component edge-apiserver -n $NAMESPACE -o yaml
    log_info "Controller 日志:"
    kubectl logs -n $NAMESPACE deployment/controller --tail=100 | grep -i apiserver
    exit 1
  }

log_success "APIServer Component 已安装"

# 等待 Console Component 安装完成
log_info "等待 Console Component 安装完成 (最长 5 分钟)..."
kubectl wait --for=jsonpath='{.status.phase}'=Installed \
  component.ext.theriseunion.io/edge-console -n $NAMESPACE --timeout=300s || {
    log_error "Console Component 安装超时"
    log_info "Component 状态:"
    kubectl get component edge-console -n $NAMESPACE -o yaml
    log_info "Controller 日志:"
    kubectl logs -n $NAMESPACE deployment/controller --tail=100 | grep -i console
    exit 1
  }

log_success "Console Component 已安装"

# 可选: 等待 Monitoring Component 安装完成
if [ "$ENABLE_MONITORING" = "true" ]; then
  log_info "等待 Monitoring Component 安装完成 (最长 10 分钟)..."
  kubectl wait --for=jsonpath='{.status.phase}'=Installed \
    component.ext.theriseunion.io/edge-monitoring -n observability-system --timeout=600s || {
      log_warn "Monitoring Component 安装超时 (非阻塞错误)"
      log_info "你可以稍后检查状态:"
      log_info "  kubectl get component edge-monitoring -n observability-system"
    }

  if kubectl get component edge-monitoring -n observability-system -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Installed"; then
    log_success "Monitoring Component 已安装"
  fi
fi

###########################################
# 步骤 4: 验证安装结果
###########################################
echo ""
log_info "========== 步骤 4/4: 验证安装结果 =========="

echo ""
log_info "查看 Pod 状态:"
kubectl get pods -n $NAMESPACE

echo ""
log_info "查看 Component CRs:"
kubectl get components -n $NAMESPACE

if [ "$ENABLE_MONITORING" = "true" ]; then
  echo ""
  log_info "查看 Monitoring Components:"
  kubectl get components -n observability-system
fi

echo ""
log_info "查看 Helm Releases:"
helm list -n $NAMESPACE

if [ "$ENABLE_MONITORING" = "true" ]; then
  helm list -n observability-system
fi

###########################################
# 部署完成
###########################################
echo ""
echo "===================================================================="
log_success "Edge Platform 安装完成！"
echo "===================================================================="
echo ""

log_info "访问方式:"
echo "  Console (Web UI):"
echo "    kubectl port-forward svc/edge-console 3000:3000 -n $NAMESPACE"
echo "    浏览器访问: http://localhost:3000"
echo ""
echo "  APIServer (REST API):"
echo "    kubectl port-forward svc/edge-apiserver 8080:8080 -n $NAMESPACE"
echo "    API 访问: http://localhost:8080"
echo ""

if [ "$ENABLE_MONITORING" = "true" ]; then
  echo "  Monitoring 访问:"
  echo "    Prometheus: kubectl port-forward svc/edge-prometheus 9090:9090 -n observability-system"
  echo "    Grafana: kubectl port-forward svc/edge-grafana 3000:3000 -n observability-system"
  echo ""
fi

log_info "管理命令:"
echo "  查看组件状态:  kubectl get components -n $NAMESPACE"
echo "  查看 Pod 状态:  kubectl get pods -n $NAMESPACE"
echo "  查看日志:      kubectl logs -n $NAMESPACE deployment/<component-name>"
echo "  更新组件:      kubectl edit component <component-name> -n $NAMESPACE"
echo ""

log_info "后续操作:"
echo "  1. 获取 OAuth Token:"
echo "     curl 'http://localhost:8080/oauth/token' \\"
echo "       --data 'grant_type=password&username=admin&password=P%4088w0rd&client_id=edge-console&client_secret=edge-secret'"
echo ""
echo "  2. 使用 Component CR 管理组件生命周期:"
echo "     - 禁用组件: kubectl patch component <name> -n $NAMESPACE --type=merge -p '{\"spec\":{\"enabled\":false}}'"
echo "     - 启用组件: kubectl patch component <name> -n $NAMESPACE --type=merge -p '{\"spec\":{\"enabled\":true}}'"
echo "     - 删除组件: kubectl delete component <name> -n $NAMESPACE"
echo ""
