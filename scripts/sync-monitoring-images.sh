#!/bin/bash

# Edge 监控组件镜像同步脚本
# 使用 skopeo 将监控组件镜像同步到私有镜像仓库

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 配置
PRIVATE_REGISTRY=${PRIVATE_REGISTRY:-quanzhenglong.com}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-edge_admin}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-""}
TARGET_NAMESPACE=${TARGET_NAMESPACE:-edge}

# 重试配置
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5}

# 显示使用说明
usage() {
    cat <<EOF
Edge 监控组件镜像同步脚本

用法:
    $0 [选项]

选项:
    -r, --registry      私有镜像仓库地址 (默认: quanzhenglong.com)
    -u, --username      镜像仓库用户名 (默认: edge_admin)
    -w, --password      镜像仓库密码 (必填)
    -n, --namespace     目标命名空间 (默认: edge)
    --dry-run           仅显示将要执行的命令，不实际执行
    -h, --help          显示帮助信息

环境变量:
    PRIVATE_REGISTRY    私有镜像仓库地址
    REGISTRY_USERNAME   镜像仓库用户名
    REGISTRY_PASSWORD   镜像仓库密码
    TARGET_NAMESPACE    目标命名空间

示例:
    # 同步所有监控组件镜像到 quanzhenglong.com/edge
    $0 -w YOUR_PASSWORD

    # 同步到自定义仓库和命名空间
    $0 -r my-registry.com -n monitoring -w YOUR_PASSWORD

    # 使用环境变量
    export REGISTRY_PASSWORD=YOUR_PASSWORD
    export PRIVATE_REGISTRY=harbor.company.com
    export TARGET_NAMESPACE=observability
    $0

    # 仅查看将要执行的命令
    $0 -w YOUR_PASSWORD --dry-run

镜像列表:
    Prometheus          prom/prometheus:v2.45.0
    Grafana             grafana/grafana:10.0.0
    AlertManager        prom/alertmanager:v0.25.0
    Kube-state-metrics  registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0
    Node-exporter       prom/node-exporter:v1.6.0
    cAdvisor            swr.cn-north-4.myhuaweicloud.com/ddn-k8s/gcr.io/cadvisor/cadvisor:v0.47.0

EOF
}

# 解析命令行参数
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            PRIVATE_REGISTRY="$2"
            shift 2
            ;;
        -u|--username)
            REGISTRY_USERNAME="$2"
            shift 2
            ;;
        -w|--password)
            REGISTRY_PASSWORD="$2"
            shift 2
            ;;
        -n|--namespace)
            TARGET_NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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

# 检查密码
if [ -z "$REGISTRY_PASSWORD" ] && [ "$DRY_RUN" = false ]; then
    print_error "未设置镜像仓库密码"
    echo "请使用 -w 参数或设置 REGISTRY_PASSWORD 环境变量"
    exit 1
fi

# 检查 skopeo 是否安装
if ! command -v skopeo &> /dev/null; then
    print_error "skopeo 未安装"
    echo ""
    echo "安装方法："
    echo "  macOS:   brew install skopeo"
    echo "  Ubuntu:  sudo apt-get install skopeo"
    echo "  CentOS:  sudo yum install skopeo"
    exit 1
fi

# 显示配置信息
print_info "============ 镜像同步配置 ============"
echo "  目标镜像仓库:     $PRIVATE_REGISTRY"
echo "  目标命名空间:     $TARGET_NAMESPACE"
echo "  用户名:           $REGISTRY_USERNAME"
echo "  Dry Run:          $DRY_RUN"
echo "======================================"
echo ""

# 同步镜像函数（带重试）
sync_image() {
    local source_image=$1
    local target_image=$2
    local description=$3

    print_step "同步镜像: $description"
    echo "  源: $source_image"
    echo "  目标: $target_image"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] 将执行: skopeo copy docker://$source_image docker://$target_image"
        return 0
    fi

    # 重试逻辑
    local retry_count=0
    local success=false

    while [ $retry_count -lt $MAX_RETRIES ]; do
        if [ $retry_count -gt 0 ]; then
            print_warn "重试 $retry_count/$MAX_RETRIES，等待 ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi

        # 使用 skopeo 同步镜像
        if skopeo copy \
            --insecure-policy \
            --multi-arch all \
            --override-arch amd64 \
            --override-os linux \
            --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
            docker://"$source_image" \
            docker://"$target_image" 2>&1; then
            print_info "✅ $description 同步成功"
            success=true
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $MAX_RETRIES ]; then
                print_warn "同步失败，准备重试..."
            fi
        fi
    done

    if [ "$success" = false ]; then
        print_error "❌ $description 同步失败（已重试 $MAX_RETRIES 次）"
        return 1
    fi
    echo ""
}

# 计数器
TOTAL_IMAGES=0
SUCCESS_COUNT=0
FAILED_COUNT=0

# ============================================================================
# 同步监控组件镜像
# ============================================================================
print_info "============================================"
print_info "开始同步监控组件镜像"
print_info "============================================"
echo ""

# Prometheus
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "prom/prometheus:v2.45.0" \
    "$PRIVATE_REGISTRY/$TARGET_NAMESPACE/prometheus:v2.45.0" \
    "Prometheus v2.45.0"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# Grafana
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "grafana/grafana:10.0.0" \
    "$PRIVATE_REGISTRY/$TARGET_NAMESPACE/grafana:10.0.0" \
    "Grafana 10.0.0"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# AlertManager
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "prom/alertmanager:v0.25.0" \
    "$PRIVATE_REGISTRY/$TARGET_NAMESPACE/alertmanager:v0.25.0" \
    "AlertManager v0.25.0"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# Kube-state-metrics
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0" \
    "$PRIVATE_REGISTRY/$TARGET_NAMESPACE/kube-state-metrics:v2.10.0" \
    "Kube-state-metrics v2.10.0"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# Node-exporter
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "prom/node-exporter:v1.6.0" \
    "$PRIVATE_REGISTRY/$TARGET_NAMESPACE/node-exporter:v1.6.0" \
    "Node-exporter v1.6.0"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# cAdvisor
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "swr.cn-north-4.myhuaweicloud.com/ddn-k8s/gcr.io/cadvisor/cadvisor:v0.47.0" \
    "$PRIVATE_REGISTRY/$TARGET_NAMESPACE/cadvisor:v0.47.0" \
    "cAdvisor v0.47.0"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# ============================================================================
# 显示同步结果
# ============================================================================
echo ""
print_info "============================================"
print_info "镜像同步完成"
print_info "============================================"
echo "  总镜像数:   $TOTAL_IMAGES"
echo "  成功数:     $SUCCESS_COUNT"
echo "  失败数:     $FAILED_COUNT"
echo "======================================"

if [ $FAILED_COUNT -gt 0 ]; then
    print_warn "部分镜像同步失败，请检查错误信息"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    print_info "Dry-run 模式完成，未实际同步镜像"
    exit 0
fi

print_info "所有监控组件镜像同步成功！"
echo ""

# 显示后续步骤
cat <<EOF
后续步骤:

1. 验证镜像已上传到私有仓库:
   skopeo list-tags docker://$PRIVATE_REGISTRY/$TARGET_NAMESPACE/prometheus
   skopeo list-tags docker://$PRIVATE_REGISTRY/$TARGET_NAMESPACE/grafana
   skopeo list-tags docker://$PRIVATE_REGISTRY/$TARGET_NAMESPACE/alertmanager
   skopeo list-tags docker://$PRIVATE_REGISTRY/$TARGET_NAMESPACE/kube-state-metrics
   skopeo list-tags docker://$PRIVATE_REGISTRY/$TARGET_NAMESPACE/node-exporter
   skopeo list-tags docker://$PRIVATE_REGISTRY/$TARGET_NAMESPACE/cadvisor

2. 安装监控组件:
   helm install edge-monitoring ./edge-monitoring \\
     -n observability-system \\
     --create-namespace \\
     --set global.imageRegistry=$PRIVATE_REGISTRY/$TARGET_NAMESPACE

3. 验证部署:
   kubectl get pods -n observability-system
   kubectl get svc -n observability-system

镜像路径说明:
  - Prometheus:        $PRIVATE_REGISTRY/$TARGET_NAMESPACE/prometheus:v2.45.0
  - Grafana:           $PRIVATE_REGISTRY/$TARGET_NAMESPACE/grafana:10.0.0
  - AlertManager:      $PRIVATE_REGISTRY/$TARGET_NAMESPACE/alertmanager:v0.25.0
  - Kube-state-metrics: $PRIVATE_REGISTRY/$TARGET_NAMESPACE/kube-state-metrics:v2.10.0
  - Node-exporter:     $PRIVATE_REGISTRY/$TARGET_NAMESPACE/node-exporter:v1.6.0
  - cAdvisor:          $PRIVATE_REGISTRY/$TARGET_NAMESPACE/cadvisor:v0.47.0

EOF
