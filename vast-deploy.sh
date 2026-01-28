#!/bin/bash

################################################################################
# VAST 组件远程部署自动化脚本
#
# 功能：
#   1. 清理本地和远程环境（防止上次部署失败的影响）
#   2. 压缩项目
#   3. 拷贝到云端节点
#   4. 解压并部署
#   5. 验证部署状态
#   6. 清理临时文件
#
# 使用方法：
#   chmod +x vast-deploy.sh
#   ./vast-deploy.sh
#
# 依赖：
#   - ssh-vpn
#   - scp-vpn
#   - tar
#   - helm
################################################################################

# 定义 ssh-vpn 和 scp-vpn 命令（WSL2 环境）
alias ssh-vpn='/mnt/c/Windows/System32/OpenSSH/ssh.exe'
alias scp-vpn='/mnt/c/Windows/System32/OpenSSH/scp.exe'

# 使 alias 在脚本中可用
shopt -s expand_aliases

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
REMOTE_HOST="root@192.168.8.98"
REMOTE_DIR="/tmp/edge-installer-temp"
ARCHIVE_NAME="edge-installer.tar.gz"
RELEASE_NAME="vast"
NAMESPACE="rise-vast-system"
CHART_PATH="./vast"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# 辅助函数
################################################################################

# 打印信息日志
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 打印成功日志
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 打印警告日志
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 打印错误日志并退出
log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    exit 1
}

# 打印分隔线
print_separator() {
    echo -e "${BLUE}================================================================================${NC}"
}

# 检查命令是否存在（支持 alias、function 和 executable）
check_command() {
    if ! type $1 &> /dev/null; then
        log_error "命令 $1 未找到，请先安装"
    fi
}

# 清理函数（脚本退出时执行）
cleanup_on_error() {
    if [ $? -ne 0 ]; then
        log_warn "检测到错误，执行清理..."
        log_info "清理本地临时文件..."
        rm -f "${PROJECT_ROOT}/${ARCHIVE_NAME}"
        log_info "清理完成"
        log_error "脚本执行失败，请查看上方错误信息"
    fi
}

# 注册清理函数
trap cleanup_on_error EXIT

################################################################################
# 主流程
################################################################################

print_separator
echo -e "${GREEN}       VAST 组件远程部署自动化脚本${NC}"
print_separator
log_info "开始执行部署流程..."
echo ""

################################################################################
# 步骤 0：前置检查
################################################################################

print_separator
log_info "步骤 0：前置检查"
print_separator

# 检查必要的命令
log_info "检查必要的命令..."
check_command ssh-vpn
check_command scp-vpn
check_command tar
log_success "所有必要命令已就绪"

# 检查项目目录
log_info "检查项目目录..."
if [ ! -d "${PROJECT_ROOT}/vast" ]; then
    log_error "vast 目录不存在：${PROJECT_ROOT}/vast"
fi
log_success "项目目录检查通过"

# 检查网络连接
log_info "检查云端节点连接..."
if ! ssh-vpn ${REMOTE_HOST} "echo '连接成功'" &> /dev/null; then
    log_error "无法连接到云端节点 ${REMOTE_HOST}"
fi
log_success "云端节点连接正常"

echo ""

################################################################################
# 步骤 1：清理环境
################################################################################

print_separator
log_info "步骤 1：清理环境（防止上次部署失败的影响）"
print_separator

# 清理本地环境
log_info "清理本地临时文件..."
if [ -f "${PROJECT_ROOT}/${ARCHIVE_NAME}" ]; then
    rm -f "${PROJECT_ROOT}/${ARCHIVE_NAME}"
    log_success "已删除本地旧的压缩包：${ARCHIVE_NAME}"
else
    log_info "本地没有旧的压缩包需要清理"
fi

# 清理远程环境
log_info "清理远程临时文件..."
ssh-vpn ${REMOTE_HOST} << EOF
# 删除旧的压缩包
if [ -f "/tmp/${ARCHIVE_NAME}" ]; then
    rm -f "/tmp/${ARCHIVE_NAME}"
    echo "已删除远程旧的压缩包：/tmp/${ARCHIVE_NAME}"
fi

# 删除旧的解压目录
if [ -d "${REMOTE_DIR}" ]; then
    rm -rf "${REMOTE_DIR}"
    echo "已删除远程旧的解压目录：${REMOTE_DIR}"
fi

echo "远程环境清理完成"
EOF

if [ $? -eq 0 ]; then
    log_success "远程环境清理完成"
else
    log_error "远程环境清理失败"
fi

echo ""

################################################################################
# 步骤 2：压缩项目
################################################################################

print_separator
log_info "步骤 2：压缩项目"
print_separator

log_info "进入项目目录：${PROJECT_ROOT}"
cd "${PROJECT_ROOT}"

# 删除旧的压缩包（如果存在）
if [ -f "${ARCHIVE_NAME}" ]; then
    rm -f "${ARCHIVE_NAME}"
    log_info "删除旧的压缩包"
fi

# 等待文件系统稳定
sleep 2

log_info "开始压缩项目（排除不必要的文件）..."
# 压缩项目，最多重试 3 次
MAX_RETRIES=3
RETRY_COUNT=0
MIN_SIZE=10000000  # 最小 10MB

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))

    tar -czf "${ARCHIVE_NAME}" \
        --exclude='.git' \
        --exclude="${ARCHIVE_NAME}" \
        --exclude='vast-*.tgz' \
        --exclude='bin' \
        . 2>&1 | grep -v "file changed as we read it" || true

    # 检查压缩包是否生成且大小合理
    if [ -f "${ARCHIVE_NAME}" ]; then
        ARCHIVE_BYTES=$(stat -f%z "${ARCHIVE_NAME}" 2>/dev/null || stat -c%s "${ARCHIVE_NAME}" 2>/dev/null || echo "0")

        # 检查文件大小是否大于最小值（10MB）
        if [ "$ARCHIVE_BYTES" -gt $MIN_SIZE ]; then
            # 压缩成功，文件大小合理
            break
        else
            log_warn "压缩包大小异常 (${ARCHIVE_BYTES} bytes)，删除并重试..."
            rm -f "${ARCHIVE_NAME}"
        fi
    fi

    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        log_warn "压缩失败或文件大小异常（第 $RETRY_COUNT 次尝试），等待 3 秒后重试..."
        sleep 3
    else
        log_error "项目压缩失败（已重试 $MAX_RETRIES 次）"
    fi
done

# 再次检查压缩包是否生成
if [ ! -f "${ARCHIVE_NAME}" ]; then
    log_error "压缩包未生成：${ARCHIVE_NAME}"
fi

# 显示压缩包大小
ARCHIVE_SIZE=$(du -h "${ARCHIVE_NAME}" | cut -f1)
log_success "项目压缩完成：${ARCHIVE_NAME} (${ARCHIVE_SIZE})"

echo ""

################################################################################
# 步骤 3：拷贝到云端节点
################################################################################

print_separator
log_info "步骤 3：拷贝压缩包到云端节点"
print_separator

log_info "开始传输文件到 ${REMOTE_HOST}:/tmp/ ..."
scp-vpn "${ARCHIVE_NAME}" "${REMOTE_HOST}:/tmp/" 2>&1

if [ $? -ne 0 ]; then
    log_error "文件传输失败"
fi

log_success "文件传输完成"

# 验证远程文件是否存在
log_info "验证远程文件..."
ssh-vpn ${REMOTE_HOST} "ls -lh /tmp/${ARCHIVE_NAME}" 2>&1

if [ $? -ne 0 ]; then
    log_error "远程文件验证失败"
fi

log_success "远程文件验证通过"

echo ""

################################################################################
# 步骤 4：解压并部署
################################################################################

print_separator
log_info "步骤 4：解压并部署 VAST 组件"
print_separator

log_info "在远程节点执行解压和部署..."
ssh-vpn ${REMOTE_HOST} << 'DEPLOY_EOF'
set -e

echo "创建临时目录..."
cd /tmp
mkdir -p edge-installer-temp
cd edge-installer-temp

echo "解压项目..."
tar -xzf ../edge-installer.tar.gz

if [ $? -ne 0 ]; then
    echo "ERROR: 解压失败"
    exit 1
fi

echo "验证 vast chart 目录..."
if [ ! -d "./vast" ]; then
    echo "ERROR: vast 目录不存在"
    exit 1
fi

echo "开始部署 VAST 组件..."
helm upgrade --install vast ./vast -n rise-vast-system --create-namespace --debug

if [ $? -ne 0 ]; then
    echo "ERROR: Helm 部署失败"
    exit 1
fi

echo "部署命令执行完成"
DEPLOY_EOF

if [ $? -ne 0 ]; then
    log_error "远程部署失败"
fi

log_success "VAST 组件部署完成"

echo ""

################################################################################
# 步骤 5：验证部署状态
################################################################################

print_separator
log_info "步骤 5：验证部署状态"
print_separator

log_info "检查 Pods 状态..."
echo ""
ssh-vpn ${REMOTE_HOST} "kubectl get pods -n ${NAMESPACE} -o wide" 2>&1
echo ""

if [ $? -ne 0 ]; then
    log_warn "Pods 状态查询失败，但部署可能已成功"
else
    log_success "Pods 状态查询完成"
fi

log_info "检查 Helm Release 状态..."
echo ""
ssh-vpn ${REMOTE_HOST} "helm list -n ${NAMESPACE}" 2>&1
echo ""

if [ $? -ne 0 ]; then
    log_warn "Helm Release 状态查询失败，但部署可能已成功"
else
    log_success "Helm Release 状态查询完成"
fi

# 等待 Pods 就绪
log_info "等待 Pods 启动（最多等待 60 秒）..."
ssh-vpn ${REMOTE_HOST} "kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=vast -n ${NAMESPACE} --timeout=60s" 2>&1 || true

echo ""

################################################################################
# 步骤 6：清理环境
################################################################################

print_separator
log_info "步骤 6：清理临时文件"
print_separator

# 清理本地环境
log_info "清理本地临时文件..."
if [ -f "${PROJECT_ROOT}/${ARCHIVE_NAME}" ]; then
    rm -f "${PROJECT_ROOT}/${ARCHIVE_NAME}"
    log_success "已删除本地压缩包：${ARCHIVE_NAME}"
else
    log_info "本地没有临时文件需要清理"
fi

# 清理远程环境
log_info "清理远程临时文件..."
ssh-vpn ${REMOTE_HOST} << EOF
# 删除压缩包
if [ -f "/tmp/${ARCHIVE_NAME}" ]; then
    rm -f "/tmp/${ARCHIVE_NAME}"
    echo "已删除远程压缩包：/tmp/${ARCHIVE_NAME}"
fi

# 删除解压目录
if [ -d "${REMOTE_DIR}" ]; then
    rm -rf "${REMOTE_DIR}"
    echo "已删除远程解压目录：${REMOTE_DIR}"
fi

echo "远程临时文件清理完成"
EOF

if [ $? -eq 0 ]; then
    log_success "远程临时文件清理完成"
else
    log_warn "远程临时文件清理失败，请手动清理"
fi

echo ""

################################################################################
# 部署完成
################################################################################

print_separator
log_success "VAST 组件部署完成！"
print_separator

echo ""
echo -e "${GREEN}部署信息汇总：${NC}"
echo "  - Release 名称: ${RELEASE_NAME}"
echo "  - 命名空间: ${NAMESPACE}"
echo "  - 云端节点: ${REMOTE_HOST}"
echo ""
echo -e "${YELLOW}后续操作：${NC}"
echo "  1. 查看 Pods 详细状态: ssh-vpn ${REMOTE_HOST} 'kubectl get pods -n ${NAMESPACE}'"
echo "  2. 查看日志: ssh-vpn ${REMOTE_HOST} 'kubectl logs -l app.kubernetes.io/instance=${RELEASE_NAME} -n ${NAMESPACE} -f'"
echo "  3. 访问 APIServer: ssh-vpn ${REMOTE_HOST} 'kubectl port-forward svc/apiserver 8443:8443 -n ${NAMESPACE}'"
echo ""
print_separator

# 退出脚本，不触发错误清理
trap - EXIT
exit 0
