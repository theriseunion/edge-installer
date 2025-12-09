#!/bin/bash

# Edge 快速部署脚本
# 使用 Helm 直接部署三个组件

# Parse command-line arguments in KEY=VALUE format.
# This allows users to pass parameters like: ./deploy.sh TAG=v1.0.0 NAMESPACE=my-ns
for arg in "$@"; do
  if [[ "$arg" =~ ^[A-Z_][A-Z0-9_]*=.*$ ]]; then
    export "$arg"
  fi
done

# 默认参数设置
NAMESPACE=${NAMESPACE:-edge-system}
KUBECONFIG_PATH=${KUBECONFIG:-~/.kube/config}
REGISTRY=${REGISTRY:-quanzhenglong.com/edge}
TAG=${TAG:-latest}
CONTROLLER_APISERVER_TAG=${CONTROLLER_APISERVER_TAG:-vast-v0.1.0-04}
PULL_POLICY=${PULL_POLICY:-Always}
ENABLE_MONITORING=${ENABLE_MONITORING:-false}
INSTALL_OPENYURT=${INSTALL_OPENYURT:-false}
OPENYURT_API_SERVER=${OPENYURT_API_SERVER:-""}
# Cert-Manager 版本与安装地址
CERT_MANAGER_VERSION=${CERT_MANAGER_VERSION:-1.14.4}
CERT_MANAGER_INSTALL_YAML="https://gh-proxy.net/https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml"


# 显示所有部署参数
echo "==================== Edge Platform 部署参数确认 ===================="
echo "命名空间 (NAMESPACE):           $NAMESPACE"
echo "Kubeconfig 路径 (KUBECONFIG):   $KUBECONFIG_PATH"
echo "镜像仓库 (REGISTRY):            $REGISTRY"
echo "镜像标签 (TAG):                 $TAG"
echo "Controller 和 API Server 镜像标签 (CONTROLLER_APISERVER_TAG): $CONTROLLER_APISERVER_TAG"
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

# 部署Cert-Manger
echo "部署 Cert-Manager..."
curl -sL "$CERT_MANAGER_INSTALL_YAML" \
  | sed -E "s|\"quay.io/jetstack/cert-manager-controller:[^\"]+\"|\"quanzhenglong.com/camp/cert-manager-controller:v${CERT_MANAGER_VERSION}\"|g" \
  | sed -E "s|\"quay.io/jetstack/cert-manager-cainjector:[^\"]+\"|\"quanzhenglong.com/camp/cert-manager-cainjector:v${CERT_MANAGER_VERSION}\"|g" \
  | sed -E "s|\"quay.io/jetstack/cert-manager-webhook:[^\"]+\"|\"quanzhenglong.com/camp/cert-manager-webhook:v${CERT_MANAGER_VERSION}\"|g" \
  | kubectl apply --validate=false -f -
kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=300s
echo "✅ Cert-Manager 部署成功"

# 等待 cert-manager webhook 完全就绪
echo "等待 cert-manager webhook 就绪..."
for i in {1..90}; do
  # 检查 webhook pod 是否就绪（使用正确的标签选择器）
  # cert-manager webhook 的标签是 app.kubernetes.io/name=webhook，不是 cert-manager-webhook
  WEBHOOK_POD_NAME=$(kubectl get pods -n cert-manager -l app.kubernetes.io/name=webhook,app.kubernetes.io/component=webhook -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$WEBHOOK_POD_NAME" ]; then
    WEBHOOK_READY=$(kubectl get pod -n cert-manager "$WEBHOOK_POD_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    WEBHOOK_PHASE=$(kubectl get pod -n cert-manager "$WEBHOOK_POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  else
    WEBHOOK_READY="False"
    WEBHOOK_PHASE="NotFound"
  fi
  
  # 检查 webhook 的 CA bundle 是否已注入
  CA_BUNDLE=$(kubectl get validatingwebhookconfiguration cert-manager-webhook -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null || echo "")
  
  # 检查 webhook 服务是否可用
  WEBHOOK_SVC=$(kubectl get svc -n cert-manager cert-manager-webhook 2>/dev/null | grep -c cert-manager-webhook || echo "0")
  
  # 检查 webhook 的 TLS 证书 secret 是否存在
  WEBHOOK_TLS_SECRET=$(kubectl get secret cert-manager-webhook-ca -n cert-manager -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")
  
  # 测试 webhook 连接（通过检查 endpoints）
  WEBHOOK_ENDPOINTS=$(kubectl get endpoints -n cert-manager cert-manager-webhook -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
  
  # 如果 Pod 是 Running 状态且 Ready 为 True，或者 Pod 不存在但其他条件满足，认为就绪
  if [ "$WEBHOOK_READY" = "True" ] && [ -n "$CA_BUNDLE" ] && [ "$CA_BUNDLE" != "null" ] && [ "$WEBHOOK_SVC" = "1" ] && [ -n "$WEBHOOK_TLS_SECRET" ] && [ -n "$WEBHOOK_ENDPOINTS" ]; then
    echo "✅ cert-manager webhook 已就绪"
    break
  fi
  
  # 如果 Pod 是 Running 状态，即使 Ready 检查失败，也认为基本就绪（可能是短暂的检查延迟）
  if [ "$WEBHOOK_PHASE" = "Running" ] && [ -n "$CA_BUNDLE" ] && [ "$CA_BUNDLE" != "null" ] && [ "$WEBHOOK_SVC" = "1" ] && [ -n "$WEBHOOK_TLS_SECRET" ] && [ -n "$WEBHOOK_ENDPOINTS" ]; then
    if [ $i -ge 30 ]; then
      echo "✅ cert-manager webhook 基本就绪（Pod Running，其他检查通过）"
      break
    fi
  fi
  
  if [ $i -eq 90 ]; then
    echo "⚠️  cert-manager webhook 就绪超时，但继续部署..."
    echo "   Pod Name: $WEBHOOK_POD_NAME"
    echo "   Pod Phase: $WEBHOOK_PHASE"
    echo "   Pod Ready: $WEBHOOK_READY"
    echo "   CA Bundle: $([ -n "$CA_BUNDLE" ] && echo "OK" || echo "missing")"
    echo "   Service: $([ "$WEBHOOK_SVC" = "1" ] && echo "OK" || echo "missing")"
    echo "   TLS Secret: $([ -n "$WEBHOOK_TLS_SECRET" ] && echo "OK" || echo "missing")"
    echo "   Endpoints: $([ -n "$WEBHOOK_ENDPOINTS" ] && echo "OK" || echo "missing")"
    break
  fi
  if [ $((i % 10)) -eq 0 ]; then
    echo "等待 cert-manager webhook 就绪... (Pod: $WEBHOOK_PHASE/$WEBHOOK_READY, CA: $([ -n "$CA_BUNDLE" ] && echo "OK" || echo "waiting"), Svc: $WEBHOOK_SVC, TLS: $([ -n "$WEBHOOK_TLS_SECRET" ] && echo "OK" || echo "waiting"), Ep: $([ -n "$WEBHOOK_ENDPOINTS" ] && echo "OK" || echo "waiting")) ($i/90)"
  fi
  sleep 2
done

# 额外等待几秒，确保 webhook 的 TLS 连接完全建立
echo "等待 webhook TLS 连接稳定..."
sleep 10

# 验证 webhook 配置
echo "验证 cert-manager webhook 配置..."
WEBHOOK_CA=$(kubectl get validatingwebhookconfiguration cert-manager-webhook -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null)
if [ -z "$WEBHOOK_CA" ] || [ "$WEBHOOK_CA" = "null" ]; then
  echo "⚠️  警告: cert-manager webhook CA bundle 未找到，webhook 验证可能失败"
  echo "   如果部署失败，请等待几分钟后重试，或手动检查 webhook 配置"
else
  echo "✅ cert-manager webhook CA bundle 已配置"
fi



# 等待 CA 证书就绪，以便在创建 APIService 时设置 caBundle
echo "等待 CA 证书就绪（用于 APIService caBundle）..."
for i in {1..60}; do
  if kubectl get secret edge-ca-cert -n $NAMESPACE &>/dev/null; then
    READY_STATUS=$(kubectl get certificate edge-ca-cert -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$READY_STATUS" = "True" ]; then
      echo "✅ CA 证书已就绪"
      break
    fi
  fi
  if [ $i -eq 60 ]; then
    echo "⚠️  CA 证书就绪超时，APIService 将在创建后通过 Job 注入 caBundle"
    break
  fi
  sleep 2
done

# 提取 CA 证书用于 Helm values
CA_BUNDLE_FOR_HELM=""
if kubectl get secret edge-ca-cert -n $NAMESPACE &>/dev/null; then
  CA_BUNDLE_FOR_HELM=$(kubectl get secret edge-ca-cert -n $NAMESPACE -o jsonpath='{.data.ca\.crt}' 2>/dev/null || \
                       kubectl get secret edge-ca-cert -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
fi

# 部署 API Server
echo "部署 API Server..."
HELM_ARGS="--set image.repository=$REGISTRY/apiserver \
  --set image.tag=$CONTROLLER_APISERVER_TAG \
  --set image.pullPolicy=$PULL_POLICY"

# 如果 CA 证书已就绪，通过 Helm values 设置 caBundle
if [ -n "$CA_BUNDLE_FOR_HELM" ]; then
  echo "通过 Helm values 设置 APIService caBundle..."
  HELM_ARGS="$HELM_ARGS --set certManager.caBundle=$CA_BUNDLE_FOR_HELM"
fi

helm upgrade --install apiserver ./edge-apiserver \
  --namespace $NAMESPACE \
  $HELM_ARGS \
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
  --set image.tag=$CONTROLLER_APISERVER_TAG \
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
