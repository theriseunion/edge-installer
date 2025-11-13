#!/bin/bash

###########################################
# Kubernetes API Server SAN 证书更新脚本
# 用途：向 K8s API Server 证书添加新的 IP 或域名
# 作者：EdgeKeel Team
###########################################

set -e

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

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户或 sudo 运行此脚本"
        exit 1
    fi
}

# 检查 kubectl 和 kubeadm
check_prerequisites() {
    log_info "检查前置条件..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装"
        exit 1
    fi

    if ! command -v kubeadm &> /dev/null; then
        log_error "kubeadm 未安装"
        exit 1
    fi

    if ! command -v openssl &> /dev/null; then
        log_error "openssl 未安装"
        exit 1
    fi

    log_info "前置条件检查通过"
}

# 备份当前证书和配置
backup_certs() {
    local backup_dir="/etc/kubernetes/pki/backup-$(date +%Y%m%d-%H%M%S)"

    log_info "备份当前证书到 ${backup_dir}..."
    mkdir -p "${backup_dir}"

    cp /etc/kubernetes/pki/apiserver.* "${backup_dir}/" 2>/dev/null || true
    cp /etc/kubernetes/admin.conf "${backup_dir}/" 2>/dev/null || true

    log_info "备份完成: ${backup_dir}"
    echo "${backup_dir}"
}

# 查看当前证书的 SAN
show_current_sans() {
    log_info "当前 API Server 证书的 SAN 列表:"
    openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A1 "Subject Alternative Name" || log_warn "未找到 SAN 信息"
}

# 获取当前的 kubeadm 配置
get_kubeadm_config() {
    log_info "获取当前 kubeadm 配置..."
    kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' > /tmp/kubeadm-config.yaml

    if [ ! -s /tmp/kubeadm-config.yaml ]; then
        log_error "无法获取 kubeadm 配置"
        exit 1
    fi

    log_info "当前配置已保存到 /tmp/kubeadm-config.yaml"
}

# 添加新的 SAN 到配置
add_san_to_config() {
    local new_san="$1"

    log_info "添加 ${new_san} 到 certSANs..."

    # 检查配置中是否已存在 apiServer.certSANs
    if grep -q "certSANs:" /tmp/kubeadm-config.yaml; then
        # 检查 SAN 是否已存在
        if grep -q "  - ${new_san}" /tmp/kubeadm-config.yaml; then
            log_warn "${new_san} 已存在于 certSANs 中"
            return 0
        fi

        # 在 certSANs 列表中添加新的 SAN
        sed -i "/certSANs:/a\  - ${new_san}" /tmp/kubeadm-config.yaml
    else
        # 如果没有 certSANs 部分，需要添加整个块
        if grep -q "apiServer:" /tmp/kubeadm-config.yaml; then
            sed -i "/apiServer:/a\  certSANs:\n  - ${new_san}" /tmp/kubeadm-config.yaml
        else
            # 添加完整的 apiServer 配置块
            cat >> /tmp/kubeadm-config.yaml <<EOF
apiServer:
  certSANs:
  - ${new_san}
EOF
        fi
    fi

    log_info "配置已更新"
}

# 重新生成 API Server 证书
regenerate_apiserver_cert() {
    log_info "删除旧的 API Server 证书..."
    rm -f /etc/kubernetes/pki/apiserver.{crt,key}

    log_info "使用新配置重新生成 API Server 证书..."
    kubeadm init phase certs apiserver --config=/tmp/kubeadm-config.yaml

    if [ ! -f /etc/kubernetes/pki/apiserver.crt ]; then
        log_error "证书生成失败"
        exit 1
    fi

    log_info "证书生成成功"
}

# 重启 API Server
restart_apiserver() {
    log_info "重启 API Server..."

    # 找到 API Server 容器
    local apiserver_container=$(crictl ps | grep kube-apiserver | awk '{print $1}')

    if [ -n "${apiserver_container}" ]; then
        # 使用 crictl 停止容器，kubelet 会自动重启
        crictl stop "${apiserver_container}" || true
        log_info "API Server 容器已停止，等待 kubelet 重启..."
        sleep 10
    else
        # 如果是静态 Pod，修改文件触发重启
        log_info "通过修改静态 Pod 配置触发重启..."
        touch /etc/kubernetes/manifests/kube-apiserver.yaml
        sleep 15
    fi

    # 等待 API Server 就绪
    log_info "等待 API Server 就绪..."
    local retry=0
    local max_retry=30

    while [ $retry -lt $max_retry ]; do
        if kubectl cluster-info &> /dev/null; then
            log_info "API Server 已就绪"
            return 0
        fi

        retry=$((retry + 1))
        echo -n "."
        sleep 2
    done

    echo ""
    log_error "API Server 重启超时"
    exit 1
}

# 验证新证书
verify_cert() {
    local target_san="$1"

    log_info "验证新证书..."
    show_current_sans

    if openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -q "${target_san}"; then
        log_info "✓ 证书中已包含 ${target_san}"
        return 0
    else
        log_error "✗ 证书中未找到 ${target_san}"
        return 1
    fi
}

# 主函数
main() {
    local new_san=""

    # 解析参数
    if [ $# -eq 0 ]; then
        echo "用法: $0 <IP或域名>"
        echo "示例: $0 116.63.165.218"
        echo "示例: $0 api.example.com"
        exit 1
    fi

    new_san="$1"

    log_info "=========================================="
    log_info "K8s API Server SAN 证书更新工具"
    log_info "=========================================="
    log_info "目标 SAN: ${new_san}"
    log_info "=========================================="

    # 执行检查
    check_root
    check_prerequisites

    # 显示当前 SAN
    show_current_sans

    # 询问确认
    echo ""
    read -p "是否继续更新证书？这将重启 API Server (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "操作已取消"
        exit 0
    fi

    # 备份
    local backup_dir=$(backup_certs)

    # 获取配置
    get_kubeadm_config

    # 添加 SAN
    add_san_to_config "${new_san}"

    # 重新生成证书
    regenerate_apiserver_cert

    # 重启 API Server
    restart_apiserver

    # 验证
    if verify_cert "${new_san}"; then
        log_info "=========================================="
        log_info "✓ 证书更新成功！"
        log_info "=========================================="
        log_info "备份位置: ${backup_dir}"
        log_info "现在可以使用 ${new_san} 访问 API Server"
        log_info ""
        log_info "测试命令:"
        log_info "kubectl --server=https://${new_san}:6443 cluster-info"
    else
        log_error "=========================================="
        log_error "证书更新失败，请检查日志"
        log_error "=========================================="
        log_error "备份位置: ${backup_dir}"
        log_error "如需回滚，请手动恢复备份的证书文件"
        exit 1
    fi
}

# 运行主函数
main "$@"
