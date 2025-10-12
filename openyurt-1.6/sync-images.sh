#!/bin/bash

# OpenYurt 1.6 镜像同步脚本
# 使用 skopeo 将 OpenYurt 镜像同步到私有镜像仓库

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
PRIVATE_REPO=${PRIVATE_REPO:-edge}
REGISTRY_USERNAME=${REGISTRY_USERNAME:-edge_admin}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-""}

# OpenYurt 版本配置
OPENYURT_VERSIONS=${OPENYURT_VERSIONS:-"v1.6.0 v1.6.1 v1.6.2"}
RAVEN_VERSION=${RAVEN_VERSION:-v0.4.1}

# 源镜像仓库
SOURCE_REGISTRY="docker.io"

# 显示使用说明
usage() {
    cat <<EOF
OpenYurt 镜像同步脚本

用法:
    $0 [选项]

选项:
    -r, --registry      私有镜像仓库地址 (默认: quanzhenglong.com)
    -p, --repo          私有镜像仓库项目名 (默认: edge)
    -u, --username      镜像仓库用户名 (默认: edge_admin)
    -w, --password      镜像仓库密码 (必填)
    -v, --versions      OpenYurt 版本列表 (默认: "v1.6.0 v1.6.1 v1.6.2")
    --raven-version     Raven 版本 (默认: v0.4.1)
    --dry-run           仅显示将要执行的命令，不实际执行
    -h, --help          显示帮助信息

环境变量:
    PRIVATE_REGISTRY    私有镜像仓库地址
    PRIVATE_REPO        私有镜像仓库项目名
    REGISTRY_USERNAME   镜像仓库用户名
    REGISTRY_PASSWORD   镜像仓库密码
    OPENYURT_VERSIONS   OpenYurt 版本列表（空格分隔）
    RAVEN_VERSION       Raven 版本

示例:
    # 同步所有 OpenYurt 1.6.x 版本镜像
    $0 -w YOUR_PASSWORD

    # 同步指定版本
    $0 -w YOUR_PASSWORD -v "v1.6.0"

    # 使用环境变量
    export REGISTRY_PASSWORD=YOUR_PASSWORD
    export OPENYURT_VERSIONS="v1.6.0 v1.6.1"
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
        -p|--repo)
            PRIVATE_REPO="$2"
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
        -v|--versions)
            OPENYURT_VERSIONS="$2"
            shift 2
            ;;
        --raven-version)
            RAVEN_VERSION="$2"
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

# 检查必填参数
if [ -z "$REGISTRY_PASSWORD" ]; then
    print_error "必须设置镜像仓库密码"
    echo ""
    usage
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
echo "  目标项目:         $PRIVATE_REPO"
echo "  用户名:           $REGISTRY_USERNAME"
echo "  OpenYurt 版本:    $OPENYURT_VERSIONS"
echo "  Raven 版本:       $RAVEN_VERSION"
echo "  Dry Run:          $DRY_RUN"
echo "======================================"
echo ""

# 同步镜像函数
sync_image() {
    local source_image=$1
    local target_image=$2
    local description=$3

    print_step "同步镜像: $description"
    echo "  源: $source_image"
    echo "  目标: $target_image"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] 将执行: skopeo copy --insecure-policy docker://$source_image docker://$target_image"
        return 0
    fi

    # 使用 skopeo 同步镜像
    if skopeo copy \
        --insecure-policy \
        --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
        --multi-arch all \
        docker://"$source_image" \
        docker://"$target_image"; then
        print_info "✅ $description 同步成功"
    else
        print_error "❌ $description 同步失败"
        return 1
    fi
    echo ""
}

# 计数器
TOTAL_IMAGES=0
SUCCESS_COUNT=0
FAILED_COUNT=0

# 同步 yurt-manager 镜像
print_info "============================================"
print_info "同步 yurt-manager 镜像"
print_info "============================================"
for version in $OPENYURT_VERSIONS; do
    TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
    if sync_image \
        "openyurt/yurt-manager:$version" \
        "$PRIVATE_REGISTRY/$PRIVATE_REPO/yurt-manager:$version" \
        "yurt-manager $version"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# 同步 yurthub 镜像
print_info "============================================"
print_info "同步 yurthub 镜像"
print_info "============================================"
for version in $OPENYURT_VERSIONS; do
    TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
    if sync_image \
        "openyurt/yurthub:$version" \
        "$PRIVATE_REGISTRY/$PRIVATE_REPO/yurthub:$version" \
        "yurthub $version"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# 同步 raven-agent 镜像
print_info "============================================"
print_info "同步 raven-agent 镜像"
print_info "============================================"
TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "openyurt/raven-agent:$RAVEN_VERSION" \
    "$PRIVATE_REGISTRY/$PRIVATE_REPO/raven-agent:$RAVEN_VERSION" \
    "raven-agent $RAVEN_VERSION"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# 同步 latest 标签
print_info "============================================"
print_info "同步 latest 标签镜像"
print_info "============================================"

# 获取最新版本（列表中的第一个）
LATEST_VERSION=$(echo $OPENYURT_VERSIONS | awk '{print $1}')

TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "openyurt/yurt-manager:$LATEST_VERSION" \
    "$PRIVATE_REGISTRY/$PRIVATE_REPO/yurt-manager:latest" \
    "yurt-manager latest"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "openyurt/yurthub:$LATEST_VERSION" \
    "$PRIVATE_REGISTRY/$PRIVATE_REPO/yurthub:latest" \
    "yurthub latest"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
if sync_image \
    "openyurt/raven-agent:$RAVEN_VERSION" \
    "$PRIVATE_REGISTRY/$PRIVATE_REPO/raven-agent:latest" \
    "raven-agent latest"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# 显示同步结果
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
   skopeo list-tags docker://$PRIVATE_REGISTRY/$PRIVATE_REPO/yurt-manager
   skopeo list-tags docker://$PRIVATE_REGISTRY/$PRIVATE_REPO/yurthub
   skopeo list-tags docker://$PRIVATE_REGISTRY/$PRIVATE_REPO/raven-agent

2. 更新 Helm values 配置使用私有镜像仓库:
   已更新以下文件：
   - yurt-manager-values.yaml
   - yurthub-values.yaml
   - raven-agent-values.yaml

3. 使用私有镜像仓库安装 OpenYurt:
   ./install.sh -a https://YOUR_API_SERVER:6443

4. 查看镜像列表文档:
   cat IMAGES.md

EOF
