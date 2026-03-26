#!/bin/bash

# Edge Platform 统一部署脚本
# 基于测试优化的自动化部署流程

set -e

# 默认参数设置
NAMESPACE=${NAMESPACE:-edge-system}
KUBECONFIG_PATH=${KUBECONFIG:-~/.kube/config}
REGISTRY=${REGISTRY:-quanzhenglong.com}
TAG=${TAG:-main}
MODE=${MODE:-all}  # all, host, member, none
CONFIG_FILE=${CONFIG_FILE:-""}

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示所有部署参数
show_parameters() {
    echo "==================== Edge Platform 部署参数确认 ===================="
    echo "命名空间 (NAMESPACE):           $NAMESPACE"
    echo "Kubeconfig 路径 (KUBECONFIG):   $KUBECONFIG_PATH"
    echo "镜像仓库 (REGISTRY):            $REGISTRY"
    echo "镜像标签 (TAG):                 $TAG"
    echo "安装模式 (MODE):                $MODE"
    echo "配置文件 (CONFIG_FILE):         ${CONFIG_FILE:-无（使用默认配置）}"
    echo ""
    echo "安装模式说明："
    echo "  all    - 安装所有组件（单集群独立部署）"
    echo "  host   - 安装控制平面组件（主机集群）"
    echo "  member - 安装成员组件（成员集群）"
    echo "  none   - 仅安装 Controller 基础设施"
    echo "===================================================================="
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖工具..."

    local missing_deps=()

    command -v kubectl >/dev/null 2>&1 || missing_deps+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_deps+=("helm")
    command -v rsync >/dev/null 2>&1 || missing_deps+=("rsync")

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少必要的依赖工具: ${missing_deps[*]}"
        echo "请先安装缺少的工具："
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi

    log_info "依赖检查通过"
}

# 检查集群连接
check_cluster() {
    log_info "检查集群连接..."

    export KUBECONFIG=$KUBECONFIG_PATH

    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "无法连接到 Kubernetes 集群"
        echo "请检查："
        echo "  1. KUBECONFIG 环境变量是否正确"
        echo "  2. 集群是否正常运行"
        echo "  3. 网络连接是否正常"
        exit 1
    fi

    log_info "集群连接正常"
    kubectl cluster-info | head -3
}

# 更新 ChartMuseum 镜像
update_chartmuseum() {
    log_info "更新 ChartMuseum 镜像..."

    if [ ! -f "Makefile" ]; then
        log_warn "未找到 Makefile，跳过 ChartMuseum 更新"
        return
    fi

    # 检查是否需要更新
    if [ "$SKIP_CHARTMUSEUM_UPDATE" = "true" ]; then
        log_info "跳过 ChartMuseum 更新（SKIP_CHARTMUSEUM_UPDATE=true）"
        return
    fi

    # 打包所有 charts
    log_info "打包 Helm charts..."
    make package-charts || {
        log_warn "Helm charts 打包失败，尝试继续..."
    }

    # 构建 ChartMuseum 镜像
    log_info "构建 ChartMuseum 镜像..."
    make docker-build-museum || {
        log_warn "ChartMuseum 镜像构建失败，尝试继续..."
    }

    # 推送镜像
    log_info "推送 ChartMuseum 镜像..."
    make docker-push-museum || {
        log_warn "ChartMuseum 镜像推送失败，尝试继续..."
    }

    log_info "ChartMuseum 镜像更新完成"
}

# 创建命名空间
create_namespaces() {
    log_info "创建必要的命名空间..."

    export KUBECONFIG=$KUBECONFIG_PATH

    # 主命名空间
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

    # 根据模式创建其他命名空间
    if [ "$MODE" = "all" ] || [ "$MODE" = "host" ]; then
        kubectl create namespace observability-system --dry-run=client -o yaml | kubectl apply -f -
        kubectl create namespace logging-system --dry-run=client -o yaml | kubectl apply -f -
        kubectl create namespace rise-vast-system --dry-run=client -o yaml | kubectl apply -f -
    fi

    log_info "命名空间创建完成"
}

# 部署 Edge Platform
deploy_platform() {
    log_info "部署 Edge Platform..."

    export KUBECONFIG=$KUBECONFIG_PATH

    # 构建 helm 命令参数
    local helm_args=(
        "upgrade"
        "--install"
        "edge-platform"
        "./edge-controller"
        "--namespace" "$NAMESPACE"
        "--set" "global.imageRegistry=$REGISTRY"
        "--set" "global.mode=$MODE"
    )

    # 如果提供了配置文件，添加到参数中
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        log_info "使用自定义配置文件: $CONFIG_FILE"
        helm_args+=("-f" "$CONFIG_FILE")
    fi

    # 镜像标签
    helm_args+=("--set" "controller.image.tag=$TAG")

    # 执行 helm 安装
    echo "执行命令: helm ${helm_args[*]}"
    helm "${helm_args[@]}" || {
        log_error "Edge Platform 部署失败"
        echo ""
        echo "故障排查建议："
        echo "  1. 检查 ChartMuseum 是否正常运行："
        echo "     kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=chartmuseum"
        echo "  2. 查看 Controller 日志："
        echo "     kubectl logs deployment/controller -n $NAMESPACE"
        echo "  3. 检查 Component 状态："
        echo "     kubectl get component -A"
        exit 1
    }

    log_info "Edge Platform 部署成功"
}

# 等待组件就绪
wait_for_ready() {
    log_info "等待组件就绪..."

    export KUBECONFIG=$KUBECONFIG_PATH

    local max_wait=300  # 最大等待 5 分钟
    local waited=0

    while [ $waited -lt $max_wait ]; do
        local not_ready=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=edge-platform --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l | tr -d ' ')

        if [ "$not_ready" -eq 0 ]; then
            log_info "所有组件已就绪"
            return 0
        fi

        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done

    log_warn "部分组件未能在预期时间内就绪"
}

# 显示部署结果
show_results() {
    export KUBECONFIG=$KUBECONFIG_PATH

    echo ""
    echo "==================== 部署结果 ===================="
    echo ""
    echo "Pod 状态："
    kubectl get pods -n $NAMESPACE
    echo ""
    echo "Component 状态："
    kubectl get component -A
    echo ""
    echo "访问方式："
    echo "  Console:    使用 NodePort 或 Ingress 访问"
    echo "  APIServer:  kubectl port-forward svc/apiserver 8080:8080 -n $NAMESPACE"
    echo "  Controller: kubectl logs deployment/controller -n $NAMESPACE"
    echo ""
    echo "================================================"
}

# 主流程
main() {
    echo "==================== Edge Platform 部署脚本 ===================="
    echo "基于测试优化的自动化部署流程"
    echo ""

    # 显示参数
    show_parameters

    # 用户确认
    if [ "$AUTO_CONFIRM" != "true" ]; then
        echo ""
        read -p "确认以上参数并开始部署？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "❌ 用户取消部署"
            exit 1
        fi
    fi

    echo ""
    log_info "开始部署 Edge Platform..."
    echo ""

    # 执行部署步骤
    check_dependencies
    check_cluster
    update_chartmuseum
    create_namespaces
    deploy_platform
    wait_for_ready
    show_results

    echo ""
    log_info "部署完成！"
}

# 执行主流程
main "$@"
