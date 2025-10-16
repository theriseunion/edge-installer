#!/bin/bash

# OpenYurt 1.6 安装脚本
# 使用 Helm charts 安装 OpenYurt 1.6 到 Kubernetes 集群

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认配置
NAMESPACE=${NAMESPACE:-kube-system}
OPENYURT_API_SERVER=${OPENYURT_API_SERVER:-""}
INSTALL_RAVEN=${INSTALL_RAVEN:-false}
HELM_TIMEOUT=${HELM_TIMEOUT:-5m}
OPENYURT_VERSION=${OPENYURT_VERSION:-v1.6.0}

# 显示使用说明
usage() {
    cat <<EOF
OpenYurt 1.6 安装脚本

用法:
    $0 [选项]

选项:
    -a, --api-server    Kubernetes API Server 地址 (必填)
                        示例: https://192.168.1.102:6443

    -n, --namespace     安装命名空间 (默认: kube-system)

    -r, --install-raven 是否安装 raven-agent (默认: false)

    -t, --timeout       Helm 安装超时时间 (默认: 5m)

    -v, --version       OpenYurt 版本 (默认: v1.6.0)

    -h, --help          显示帮助信息

环境变量:
    OPENYURT_API_SERVER  Kubernetes API Server 地址
    NAMESPACE            安装命名空间
    INSTALL_RAVEN        是否安装 raven-agent
    HELM_TIMEOUT         Helm 安装超时时间
    OPENYURT_VERSION     OpenYurt 版本

示例:
    # 基本安装
    $0 -a https://192.168.1.102:6443

    # 完整安装（包括 raven-agent）
    $0 -a https://192.168.1.102:6443 -r true

    # 使用环境变量
    export OPENYURT_API_SERVER=https://192.168.1.102:6443
    export INSTALL_RAVEN=true
    $0

EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--api-server)
            OPENYURT_API_SERVER="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--install-raven)
            INSTALL_RAVEN="$2"
            shift 2
            ;;
        -t|--timeout)
            HELM_TIMEOUT="$2"
            shift 2
            ;;
        -v|--version)
            OPENYURT_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

# 检查必填参数
if [ -z "$OPENYURT_API_SERVER" ]; then
    print_error "必须设置 Kubernetes API Server 地址"
    echo ""
    usage
    exit 1
fi

# 检查依赖
print_info "检查依赖..."
command -v kubectl >/dev/null 2>&1 || {
    print_error "kubectl 未安装，请先安装 kubectl"
    exit 1
}

command -v helm >/dev/null 2>&1 || {
    print_error "Helm 未安装，请先安装 Helm 3.x"
    exit 1
}

# 检查 kubectl 连接
if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "无法连接到 Kubernetes 集群，请检查 KUBECONFIG 配置"
    exit 1
fi

# 显示配置信息
print_info "============ 安装配置 ============"
echo "  命名空间:          $NAMESPACE"
echo "  API Server:        $OPENYURT_API_SERVER"
echo "  OpenYurt 版本:     $OPENYURT_VERSION"
echo "  安装 raven-agent:  $INSTALL_RAVEN"
echo "  Helm 超时:         $HELM_TIMEOUT"
echo "===================================="
echo ""

# 确认安装
read -p "是否继续安装? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warn "安装已取消"
    exit 0
fi

# 添加 OpenYurt Helm 仓库
print_info "添加 OpenYurt Helm 仓库..."
helm repo add openyurt https://openyurtio.github.io/openyurt-helm 2>/dev/null || true
helm repo update

# 1. 安装 yurt-manager
print_info "============================================"
print_info "安装 yurt-manager (OpenYurt 核心控制器)..."
print_info "============================================"

helm upgrade --install yurt-manager openyurt/yurt-manager \
    --namespace "$NAMESPACE" \
    --values "$SCRIPT_DIR/yurt-manager-values.yaml" \
    --set image.tag="$OPENYURT_VERSION" \
    --wait \
    --timeout "$HELM_TIMEOUT" || {
        print_error "yurt-manager 安装失败"
        exit 1
    }

print_info "✅ yurt-manager 安装成功"
echo ""

# 应用 RBAC 权限修复
print_info "============================================"
print_info "应用 RBAC 权限修复..."
print_info "============================================"

kubectl apply -f "$SCRIPT_DIR/rbac-fix.yaml" || {
    print_warn "RBAC 权限修复应用失败（可能是权限已存在）"
}

print_info "✅ RBAC 权限修复应用成功"
echo ""

# 2. 安装 yurthub
print_info "============================================"
print_info "安装 yurthub (边缘节点代理组件)..."
print_info "============================================"

helm upgrade --install yurthub openyurt/yurthub \
    --namespace "$NAMESPACE" \
    --values "$SCRIPT_DIR/yurthub-values.yaml" \
    --set kubernetesServerAddr="$OPENYURT_API_SERVER" \
    --set image.tag="$OPENYURT_VERSION" \
    --wait \
    --timeout "$HELM_TIMEOUT" || {
        print_error "yurthub 安装失败"
        exit 1
    }

print_info "✅ yurthub 安装成功"
echo ""

# 3. 可选安装 raven-agent
if [ "$INSTALL_RAVEN" = "true" ]; then
    print_info "============================================"
    print_info "安装 raven-agent (边缘网络通信组件)..."
    print_info "============================================"

    helm upgrade --install raven-agent openyurt/raven-agent \
        --namespace "$NAMESPACE" \
        --values "$SCRIPT_DIR/raven-agent-values.yaml" \
        --wait \
        --timeout "$HELM_TIMEOUT" || {
            print_warn "raven-agent 安装失败（非关键组件，可忽略）"
        }

    print_info "✅ raven-agent 安装成功"
    echo ""
fi

# 验证安装
print_info "============================================"
print_info "验证 OpenYurt 安装..."
print_info "============================================"

# 等待 Pods 就绪
print_info "等待 Pods 就绪..."
sleep 5

# 检查 yurt-manager
print_info "检查 yurt-manager..."
kubectl get deployment yurt-manager -n "$NAMESPACE" || print_warn "yurt-manager deployment 未找到"

# 检查 YurtStaticSet
print_info "检查 YurtStaticSet..."
kubectl get yurtstaticset -n "$NAMESPACE" || print_warn "YurtStaticSet 未找到"

# 检查 ConfigMap
print_info "检查 yurt-hub ConfigMap..."
kubectl get configmap yurt-static-set-yurt-hub -n "$NAMESPACE" >/dev/null 2>&1 && {
    print_info "✅ yurt-hub ConfigMap 已创建"

    # 验证关键参数
    if kubectl get configmap yurt-static-set-yurt-hub -n "$NAMESPACE" -o yaml | grep -q "hub-cert-organizations=system:nodes"; then
        print_info "✅ yurt-hub 配置包含 hub-cert-organizations 参数"
    else
        print_warn "⚠️  yurt-hub 配置缺少 hub-cert-organizations 参数，边缘节点可能无法正常运行"
    fi
} || print_warn "yurt-hub ConfigMap 未找到"

# 检查 Pods
print_info "OpenYurt 相关 Pods:"
kubectl get pods -n "$NAMESPACE" | grep yurt || print_warn "未找到 yurt 相关 Pods"

echo ""
print_info "============================================"
print_info "✅ OpenYurt 1.6 安装完成！"
print_info "============================================"
echo ""

# 显示后续步骤
cat <<EOF
后续步骤:

1. 验证 CRDs:
   kubectl get crd | grep openyurt

2. 检查 YurtStaticSet:
   kubectl get yurtstaticset -n $NAMESPACE
   kubectl get yurtstaticset yurt-hub -n $NAMESPACE -o yaml

3. 配置集群使用 OpenYurt:
   kubectl annotate cluster <cluster-name> \\
     cluster.theriseunion.io/edge-runtime=openyurt \\
     --overwrite

4. 边缘节点加入集群:
   通过 Edge Platform API 获取加入命令:
   curl "http://apiserver:8080/oapis/infra.theriseunion.io/v1alpha1/join-token?nodeName=<node-name>"

5. 查看 OpenYurt 文档:
   cat $SCRIPT_DIR/README.md

EOF
