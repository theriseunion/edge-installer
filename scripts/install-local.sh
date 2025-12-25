#!/usr/bin/env bash

set -euo pipefail

# Edge Platform Local Installation Script
# 使用 main-local 标签的本地镜像进行安装

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDGE_INSTALLER_DIR="${SCRIPT_DIR}/.."
NAMESPACE="${NAMESPACE:-edge-system}"
MODE="${MODE:-host}"  # host | member | all

# 镜像配置
REGISTRY="quanzhenglong.com/edge"
TAG="main-qzl"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
    echo -e "\n${BLUE}==>${NC} $*"
}

print_banner() {
    cat <<EOF

${BLUE}╔══════════════════════════════════════════════════════════╗
║                                                          ║
║         Edge Platform 本地安装脚本                        ║
║                                                          ║
║  镜像仓库: ${REGISTRY}                  ║
║  镜像标签: ${TAG}                             ║
║  安装模式: ${MODE}                                  ║
║  命名空间: ${NAMESPACE}                          ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝${NC}

EOF
}

check_prerequisites() {
    log_step "检查前置条件"

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装,请先安装 kubectl"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm 未安装,请先安装 helm"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群,请检查 kubeconfig"
        exit 1
    fi

    log_info "✓ 前置条件检查通过"
}

check_images() {
    log_step "检查本地镜像"

    local images=(
        "${REGISTRY}/edge-museum:${TAG}"
        "${REGISTRY}/apiserver:${TAG}"
        "${REGISTRY}/controller:${TAG}"
    )

    if [[ "${MODE}" == "host" ]] || [[ "${MODE}" == "all" ]]; then
        images+=("${REGISTRY}/console:${TAG}")
    fi

    for img in "${images[@]}"; do
        log_info "检查镜像: ${img}"
    done

    log_warn "请确保以下镜像已经构建并推送到镜像仓库:"
    for img in "${images[@]}"; do
        echo "  - ${img}"
    done

    echo ""
    read -p "镜像是否已就绪? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "请先构建并推送镜像"
        exit 1
    fi
}

install_unified() {
    log_step "使用统一方式安装 (单 Helm 命令)"

    cd "${EDGE_INSTALLER_DIR}"

    local helm_args=(
        "edge-platform"
        "./edge-controller"
        "--namespace" "${NAMESPACE}"
        "--create-namespace"
        "--set" "global.mode=${MODE}"
        "--set" "global.imageRegistry=${REGISTRY}"
        "--set" "controller.image.tag=${TAG}"
        "--set" "chartmuseum.image.tag=${TAG}"
        "--set" "autoInstall.apiserver.values.image.repository=${REGISTRY}/apiserver"
        "--set" "autoInstall.apiserver.values.image.tag=${TAG}"
        "--set" "autoInstall.apiserver.values.image.pullPolicy=IfNotPresent"
    )

    if [[ "${MODE}" == "host" ]] || [[ "${MODE}" == "all" ]]; then
        helm_args+=(
            "--set" "autoInstall.console.values.image.repository=${REGISTRY}/console"
            "--set" "autoInstall.console.values.image.tag=${TAG}"
            "--set" "autoInstall.console.values.image.pullPolicy=IfNotPresent"
        )
    fi

    log_info "执行 Helm 安装..."
    helm install "${helm_args[@]}"

    log_info "✓ Helm 安装命令已执行"
}

wait_for_controller() {
    log_step "等待 Controller 就绪"

    kubectl wait --for=condition=available deployment/edge-platform-controller \
        -n "${NAMESPACE}" --timeout=300s

    log_info "✓ Controller 已就绪"
}

wait_for_chartmuseum() {
    log_step "等待 ChartMuseum 就绪"

    kubectl wait --for=condition=available deployment/edge-platform-chartmuseum \
        -n "${NAMESPACE}" --timeout=300s

    log_info "✓ ChartMuseum 已就绪"
}

verify_installation() {
    log_step "验证安装"

    echo ""
    log_info "检查 Pods 状态:"
    kubectl get pods -n "${NAMESPACE}"

    echo ""
    log_info "检查 Component CRs:"
    kubectl get components -A

    echo ""
    log_info "检查 Helm Releases:"
    helm list -n "${NAMESPACE}"
}

print_next_steps() {
    cat <<EOF

${GREEN}╔══════════════════════════════════════════════════════════╗
║                                                          ║
║               安装完成!                                   ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝${NC}

${YELLOW}后续步骤:${NC}

1. 检查组件状态:
   ${BLUE}kubectl get components -A${NC}
   ${BLUE}kubectl get pods -n ${NAMESPACE}${NC}

2. 查看 APIServer 日志:
   ${BLUE}kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=apiserver${NC}

3. 查看 Controller 日志:
   ${BLUE}kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=controller${NC}

EOF

    if [[ "${MODE}" == "host" ]] || [[ "${MODE}" == "all" ]]; then
        cat <<EOF
4. 访问 Console (需要端口转发):
   ${BLUE}kubectl port-forward -n ${NAMESPACE} svc/console 3000:3000${NC}
   然后访问: ${BLUE}http://localhost:3000${NC}

EOF
    fi

    cat <<EOF
${YELLOW}故障排查:${NC}

- 查看 Component 状态: ${BLUE}kubectl describe component <name> -n ${NAMESPACE}${NC}
- 查看 ChartMuseum 日志: ${BLUE}kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=chartmuseum${NC}
- 查看 Controller 日志: ${BLUE}kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=controller${NC}

${YELLOW}卸载:${NC}
   ${BLUE}helm uninstall edge-platform -n ${NAMESPACE}${NC}

EOF
}

main() {
    print_banner
    check_prerequisites
    check_images
    install_unified
    wait_for_controller
    wait_for_chartmuseum

    log_info "等待 30 秒,让 Component Controller 处理 Component CRs..."
    sleep 30

    verify_installation
    print_next_steps

    log_info "安装流程已完成!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --help)
            cat <<EOF
使用方法: $0 [选项]

选项:
  --mode MODE          安装模式 (host|member|all, 默认: host)
  --namespace NS       命名空间 (默认: edge-system)
  --registry REGISTRY  镜像仓库 (默认: quanzhenglong.com/edge)
  --tag TAG            镜像标签 (默认: main-local)
  --help               显示此帮助信息

示例:
  # 使用默认配置安装 Host 集群
  $0

  # 安装 Member 集群
  $0 --mode member

  # 使用自定义镜像仓库
  $0 --registry my-registry.com/edge --tag v1.0.0

环境变量:
  MODE       安装模式
  NAMESPACE  命名空间
EOF
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# Run main function
main
