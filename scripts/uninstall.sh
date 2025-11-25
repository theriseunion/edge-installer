#!/bin/bash

# Edge Platform 卸载脚本

set -e

# 配置变量
NAMESPACE="edge-system"
KUBECONFIG_FILE=""
DELETE_NAMESPACE="false"
DELETE_CRD="false"

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
Edge Platform 卸载脚本

用法: $0 [OPTIONS]

选项:
    -n, --namespace NAMESPACE       卸载命名空间 (默认: edge-system)
    -k, --kubeconfig FILE          kubeconfig 文件路径
    --delete-namespace             删除命名空间
    --delete-crd                   删除 CRD 资源
    -h, --help                     显示此帮助信息

示例:
    # 基本卸载 (保留命名空间和 CRD)
    $0

    # 完全卸载 (删除命名空间和 CRD)
    $0 --delete-namespace --delete-crd

    # 指定 kubeconfig 卸载
    $0 -k ~/.kube/116.63.161.198.config

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
            --delete-namespace)
                DELETE_NAMESPACE="true"
                shift
                ;;
            --delete-crd)
                DELETE_CRD="true"
                shift
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

# 卸载 Helm releases
uninstall_helm_releases() {
    print_info "卸载 Edge 组件..."

    local releases=("console" "apiserver" "controller")

    for release in "${releases[@]}"; do
        if helm list -n "$NAMESPACE" | grep -q "$release"; then
            print_info "卸载 Helm release: $release"
            helm uninstall "$release" -n "$NAMESPACE"
            print_success "已卸载: $release"
        else
            print_warning "Helm release 不存在: $release"
        fi
    done
}

# 删除 CRD 资源
delete_crds() {
    if [[ "$DELETE_CRD" != "true" ]]; then
        print_info "跳过 CRD 删除 (使用 --delete-crd 删除 CRD)"
        return
    fi

    print_info "删除 Edge CRD 资源..."

    local crds=(
        "edgeconfigurations.installer.edge.theriseunion.io"
        "roletemplates.iam.theriseunion.io"
        "roles.iam.theriseunion.io"
    )

    for crd in "${crds[@]}"; do
        if kubectl get crd "$crd" &> /dev/null; then
            print_info "删除 CRD: $crd"
            kubectl delete crd "$crd"
            print_success "已删除 CRD: $crd"
        else
            print_warning "CRD 不存在: $crd"
        fi
    done
}

# 删除命名空间
delete_namespace() {
    if [[ "$DELETE_NAMESPACE" != "true" ]]; then
        print_info "跳过命名空间删除 (使用 --delete-namespace 删除命名空间)"
        return
    fi

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_info "删除命名空间: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE"
        print_success "已删除命名空间: $NAMESPACE"
    else
        print_warning "命名空间不存在: $NAMESPACE"
    fi
}

# 清理残留资源
cleanup_remaining_resources() {
    print_info "清理残留资源..."

    # 清理 EdgeConfiguration 资源
    if kubectl get edgeconfigurations -n "$NAMESPACE" &> /dev/null; then
        kubectl delete edgeconfigurations --all -n "$NAMESPACE"
    fi

    # 清理 ClusterRole 和 ClusterRoleBinding
    local cluster_resources=(
        "clusterrole/edge-installer"
        "clusterrolebinding/edge-installer"
    )

    for resource in "${cluster_resources[@]}"; do
        if kubectl get "$resource" &> /dev/null; then
            print_info "删除: $resource"
            kubectl delete "$resource"
        fi
    done
}

# 主函数
main() {
    print_info "Edge Platform 卸载脚本启动"
    print_info "======================================"

    parse_args "$@"
    setup_kubectl

    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        print_error "无法连接到 Kubernetes 集群"
        exit 1
    fi

    uninstall_helm_releases
    cleanup_remaining_resources
    delete_crds
    delete_namespace

    print_success "Edge Platform 卸载完成！"

    if [[ "$DELETE_NAMESPACE" != "true" ]] || [[ "$DELETE_CRD" != "true" ]]; then
        echo
        print_info "提示:"
        [[ "$DELETE_NAMESPACE" != "true" ]] && echo "  命名空间 '$NAMESPACE' 已保留"
        [[ "$DELETE_CRD" != "true" ]] && echo "  CRD 资源已保留"
        echo "  使用 --delete-namespace --delete-crd 进行完全清理"
    fi
}

# 执行主函数
main "$@"