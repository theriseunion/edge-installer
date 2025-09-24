#!/bin/bash

# Edge Platform 安装脚本
# 基于 Kubernetes 的安装模式，使用 Helm charts 部署

set -e

# 配置变量
NAMESPACE="edge-system"
RELEASE_NAME="edge"
KUBECONFIG_FILE=""
DRY_RUN="false"
SKIP_CRD_INSTALL="false"
TIMEOUT="600s"
REGISTRY="quanzhenglong.com/edge"
IMAGE_TAG="main"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
Edge Platform 安装脚本

用法: $0 [OPTIONS]

选项:
    -n, --namespace NAMESPACE       安装命名空间 (默认: edge-system)
    -k, --kubeconfig FILE          kubeconfig 文件路径
    -r, --registry REGISTRY        镜像仓库地址 (默认: quanzhenglong.com/edge)
    --tag TAG                      镜像标签 (默认: main)
    --dry-run                      执行 dry-run，不实际安装
    --skip-crd-install             跳过 CRD 安装 (用于升级)
    -t, --timeout TIMEOUT         安装超时时间 (默认: 600s)
    -h, --help                     显示此帮助信息

示例:
    # 基本安装
    $0

    # 指定 kubeconfig 安装
    $0 -k ~/.kube/116.63.161.198.config

    # 自定义命名空间安装
    $0 -n my-edge-system

    # Dry-run 预览
    $0 --dry-run

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -k|--kubeconfig)
                KUBECONFIG_FILE="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --skip-crd-install)
                SKIP_CRD_INSTALL="true"
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查依赖工具
check_dependencies() {
    print_info "检查依赖工具..."

    local missing_deps=()

    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi

    if ! command -v helm &> /dev/null; then
        missing_deps+=("helm")
    fi

    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        print_error "缺少必需的依赖工具: ${missing_deps[*]}"
        print_info "请先安装缺少的工具后再运行此脚本"
        exit 1
    fi

    print_success "依赖工具检查通过"
}

# 设置 kubectl 配置
setup_kubectl() {
    if [[ -n "$KUBECONFIG_FILE" ]]; then
        if [[ ! -f "$KUBECONFIG_FILE" ]]; then
            print_error "kubeconfig 文件不存在: $KUBECONFIG_FILE"
            exit 1
        fi
        export KUBECONFIG="$KUBECONFIG_FILE"
        print_info "使用 kubeconfig: $KUBECONFIG_FILE"
    fi
}

# 检查集群连接
check_cluster_connection() {
    print_info "检查 Kubernetes 集群连接..."

    if ! kubectl cluster-info &> /dev/null; then
        print_error "无法连接到 Kubernetes 集群"
        print_info "请检查 kubeconfig 配置或集群状态"
        exit 1
    fi

    local cluster_version
    cluster_version=$(kubectl version --client=false -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "unknown")
    print_success "成功连接到 Kubernetes 集群 (版本: $cluster_version)"
}

# 创建命名空间
create_namespace() {
    print_info "创建命名空间: $NAMESPACE"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "[DRY-RUN] 跳过命名空间创建"
        return
    fi

    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "命名空间 $NAMESPACE 创建/更新完成"
}

# 添加 Helm 仓库 (如果有的话)
setup_helm_repo() {
    print_info "设置 Helm 仓库..."

    # 这里可以添加私有 Helm 仓库设置
    # helm repo add edge https://charts.edge.io
    # helm repo update

    print_success "Helm 仓库设置完成"
}

# 安装 Edge Controller
install_controller() {
    print_info "安装 Edge Controller..."

    local chart_path="../charts/edge-controller"
    local values_args=""

    # 设置镜像仓库
    values_args="$values_args --set image.repository=$REGISTRY/edge-controller"
    values_args="$values_args --set image.tag=main"

    if [[ "$DRY_RUN" == "true" ]]; then
        values_args="$values_args --dry-run"
    fi

    if [[ "$SKIP_CRD_INSTALL" == "true" ]]; then
        values_args="$values_args --skip-crds"
    fi

    helm upgrade --install \
        "$RELEASE_NAME-controller" \
        "$chart_path" \
        --namespace "$NAMESPACE" \
        --timeout "$TIMEOUT" \
        $values_args

    if [[ "$DRY_RUN" != "true" ]]; then
        print_success "Edge Controller 安装完成"
    else
        print_warning "[DRY-RUN] Edge Controller 预览完成"
    fi
}

# 安装 Edge API Server
install_apiserver() {
    print_info "安装 Edge API Server..."

    local chart_path="../charts/edge-apiserver"
    local values_args=""

    # 设置镜像仓库
    values_args="$values_args --set image.repository=$REGISTRY/edge-apiserver"
    values_args="$values_args --set image.tag=main"

    if [[ "$DRY_RUN" == "true" ]]; then
        values_args="$values_args --dry-run"
    fi

    helm upgrade --install \
        "$RELEASE_NAME-apiserver" \
        "$chart_path" \
        --namespace "$NAMESPACE" \
        --timeout "$TIMEOUT" \
        $values_args

    if [[ "$DRY_RUN" != "true" ]]; then
        print_success "Edge API Server 安装完成"
    else
        print_warning "[DRY-RUN] Edge API Server 预览完成"
    fi
}

# 安装 Edge Console
install_console() {
    print_info "安装 Edge Console..."

    local chart_path="../charts/edge-console"
    local values_args=""

    # 设置镜像仓库
    values_args="$values_args --set image.repository=$REGISTRY/edge-console"
    values_args="$values_args --set image.tag=main"

    if [[ "$DRY_RUN" == "true" ]]; then
        values_args="$values_args --dry-run"
    fi

    helm upgrade --install \
        "$RELEASE_NAME-console" \
        "$chart_path" \
        --namespace "$NAMESPACE" \
        --timeout "$TIMEOUT" \
        $values_args

    if [[ "$DRY_RUN" != "true" ]]; then
        print_success "Edge Console 安装完成"
    else
        print_warning "[DRY-RUN] Edge Console 预览完成"
    fi
}

# 等待部署就绪
wait_for_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "[DRY-RUN] 跳过部署状态检查"
        return
    fi

    print_info "等待部署就绪..."

    local deployments=("$RELEASE_NAME-controller" "$RELEASE_NAME-apiserver" "$RELEASE_NAME-console")

    for deployment in "${deployments[@]}"; do
        print_info "等待部署 $deployment 就绪..."
        if kubectl rollout status deployment/"$deployment" -n "$NAMESPACE" --timeout="$TIMEOUT"; then
            print_success "部署 $deployment 已就绪"
        else
            print_error "部署 $deployment 未能在规定时间内就绪"
            return 1
        fi
    done
}

# 显示访问信息
show_access_info() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "[DRY-RUN] 跳过访问信息显示"
        return
    fi

    print_info "Edge Platform 安装完成！"
    echo
    print_info "访问信息:"
    echo "  命名空间: $NAMESPACE"
    echo
    print_info "端口转发命令:"
    echo "  # API Server"
    echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-apiserver 8080:8080"
    echo
    echo "  # Web Console"
    echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-console 3000:3000"
    echo
    print_info "访问地址:"
    echo "  API Server: http://localhost:8080"
    echo "  Web Console: http://localhost:3000"
    echo
    print_info "检查部署状态:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl get svc -n $NAMESPACE"
}

# 主函数
main() {
    print_info "Edge Platform 安装脚本启动"
    print_info "======================================"

    parse_args "$@"
    check_dependencies
    setup_kubectl
    check_cluster_connection
    create_namespace
    setup_helm_repo

    # 按顺序安装组件
    install_controller
    install_apiserver
    install_console

    wait_for_deployment
    show_access_info

    print_success "Edge Platform 安装脚本执行完成！"
}

# 执行主函数
main "$@"