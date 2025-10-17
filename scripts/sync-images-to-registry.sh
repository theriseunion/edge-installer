#!/bin/bash

# EdgeX Foundry + yurt-iot-dock 镜像同步脚本
# 使用 skopeo 将镜像同步到私有镜像仓库

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

# EdgeX Foundry Minnesota (v3.0) 版本
EDGEX_VERSION=${EDGEX_VERSION:-3.0.0}

# 源镜像仓库（可以使用阿里云镜像加速）
# 默认: docker.io
# 阿里云: registry.cn-hangzhou.aliyuncs.com
SOURCE_REGISTRY=${SOURCE_REGISTRY:-docker.io}

# 重试配置
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5}

# 显示使用说明
usage() {
    cat <<EOF
EdgeX Foundry + yurt-iot-dock 镜像同步脚本

用法:
    $0 [选项]

选项:
    -r, --registry      私有镜像仓库地址 (默认: quanzhenglong.com)
    -u, --username      镜像仓库用户名 (默认: edge_admin)
    -w, --password      镜像仓库密码 (必填)
    -v, --edgex-version EdgeX 版本 (默认: 3.0.0)
    --dry-run           仅显示将要执行的命令，不实际执行
    -h, --help          显示帮助信息

环境变量:
    PRIVATE_REGISTRY    私有镜像仓库地址
    REGISTRY_USERNAME   镜像仓库用户名
    REGISTRY_PASSWORD   镜像仓库密码
    EDGEX_VERSION       EdgeX Foundry 版本

示例:
    # 同步所有 EdgeX Minnesota 镜像
    $0 -w YOUR_PASSWORD

    # 使用环境变量
    export REGISTRY_PASSWORD=YOUR_PASSWORD
    export EDGEX_VERSION=3.0.0
    $0

    # 仅查看将要执行的命令
    $0 -w YOUR_PASSWORD --dry-run

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
        -v|--edgex-version)
            EDGEX_VERSION="$2"
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
echo "  源镜像仓库:       $SOURCE_REGISTRY"
echo "  目标镜像仓库:     $PRIVATE_REGISTRY"
echo "  用户名:           $REGISTRY_USERNAME"
echo "  EdgeX 版本:       $EDGEX_VERSION"
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
        # --multi-arch all: 同步所有架构
        # --override-arch amd64: 强制使用 amd64 架构（用于 Kubernetes 集群）
        # --override-os linux: 强制使用 linux 系统
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
# 1. 同步 yurt-iot-dock 镜像
# ============================================================================
print_info "============================================"
print_info "第 1 步: 同步 yurt-iot-dock 镜像"
print_info "============================================"
echo ""

# yurt-iot-dock v1.6.0-fixed -> openyurt/yurt-iot-dock:v1.6.0-fixed
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "$PRIVATE_REGISTRY/edge/yurt-iot-dock:v1.6.0-fixed" \
    "$PRIVATE_REGISTRY/openyurt/yurt-iot-dock:v1.6.0-fixed" \
    "yurt-iot-dock v1.6.0-fixed"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# yurt-iot-dock v1.6.0-fixed -> openyurt/yurt-iot-dock:latest
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "$PRIVATE_REGISTRY/edge/yurt-iot-dock:v1.6.0-fixed" \
    "$PRIVATE_REGISTRY/openyurt/yurt-iot-dock:latest" \
    "yurt-iot-dock latest"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# ============================================================================
# 2. 同步 EdgeX 核心服务镜像
# ============================================================================
print_info "============================================"
print_info "第 2 步: 同步 EdgeX 核心服务镜像"
print_info "============================================"
echo ""

# edgex-core-command
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/core-command:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/core-command:$EDGEX_VERSION" \
    "edgex-core-command $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# edgex-core-metadata
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/core-metadata:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/core-metadata:$EDGEX_VERSION" \
    "edgex-core-metadata $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# edgex-core-data
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/core-data:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/core-data:$EDGEX_VERSION" \
    "edgex-core-data $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# edgex-support-notifications
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/support-notifications:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/support-notifications:$EDGEX_VERSION" \
    "edgex-support-notifications $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# edgex-support-scheduler
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/support-scheduler:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/support-scheduler:$EDGEX_VERSION" \
    "edgex-support-scheduler $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# ============================================================================
# 3. 同步 EdgeX 设备服务镜像
# ============================================================================
print_info "============================================"
print_info "第 3 步: 同步 EdgeX 设备服务镜像"
print_info "============================================"
echo ""

# edgex-device-virtual
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/device-virtual:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/device-virtual:$EDGEX_VERSION" \
    "edgex-device-virtual $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# edgex-device-rest
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/device-rest:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/device-rest:$EDGEX_VERSION" \
    "edgex-device-rest $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# edgex-device-mqtt (可选)
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/device-mqtt:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/device-mqtt:$EDGEX_VERSION" \
    "edgex-device-mqtt $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# edgex-device-modbus (可选)
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/device-modbus:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/device-modbus:$EDGEX_VERSION" \
    "edgex-device-modbus $EDGEX_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# ============================================================================
# 4. 同步 EdgeX 基础设施镜像
# ============================================================================
print_info "============================================"
print_info "第 4 步: 同步 EdgeX 基础设施镜像"
print_info "============================================"
echo ""

# Consul
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "consul:1.15" \
    "$PRIVATE_REGISTRY/edgexfoundry/consul:1.15" \
    "consul 1.15"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# Redis
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "redis:7.0-alpine" \
    "$PRIVATE_REGISTRY/edgexfoundry/redis:7.0-alpine" \
    "redis 7.0-alpine"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# ============================================================================
# 5. 同步 EdgeX 配置引导镜像
# ============================================================================
print_info "============================================"
print_info "第 5 步: 同步 EdgeX 配置引导镜像"
print_info "============================================"
echo ""

# edgex-core-common-config-bootstrapper
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "edgexfoundry/core-common-config-bootstrapper:$EDGEX_VERSION" \
    "$PRIVATE_REGISTRY/edgexfoundry/core-common-config-bootstrapper:$EDGEX_VERSION" \
    "edgex-core-common-config-bootstrapper $EDGEX_VERSION"; then
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

print_info "所有镜像同步成功！"
echo ""

# 显示后续步骤
cat <<EOF
后续步骤:

1. 验证镜像已上传到私有仓库:
   # 验证 yurt-iot-dock
   skopeo list-tags docker://$PRIVATE_REGISTRY/openyurt/yurt-iot-dock

   # 验证 EdgeX 核心组件（示例）
   skopeo list-tags docker://$PRIVATE_REGISTRY/edgexfoundry/core-command
   skopeo list-tags docker://$PRIVATE_REGISTRY/edgexfoundry/core-metadata
   skopeo list-tags docker://$PRIVATE_REGISTRY/edgexfoundry/device-virtual

2. 创建 PlatformAdmin CR 使用私有镜像仓库:
   apiVersion: iot.openyurt.io/v1beta1
   kind: PlatformAdmin
   metadata:
     name: edgex-sample
   spec:
     version: minnesota
     platform: edgex
     imageRegistry: $PRIVATE_REGISTRY  # 注意：不要加 /edge 或 /openyurt
     nodepools:
       - edge-nodepool
     components:
       - name: yurt-iot-dock
       - name: edgex-device-virtual
       - name: edgex-device-rest

3. 部署 EdgeX Foundry:
   kubectl apply -f platformadmin.yaml

4. 验证部署:
   kubectl get pods -l iot.openyurt.io/platform=edgex
   kubectl get platformadmin edgex-sample

镜像路径说明:
  - yurt-iot-dock: $PRIVATE_REGISTRY/openyurt/yurt-iot-dock:latest
  - EdgeX 组件:    $PRIVATE_REGISTRY/edgexfoundry/<component>:$EDGEX_VERSION

EOF
