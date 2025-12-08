#!/usr/bin/env bash

set -euo pipefail

# ChartMuseum Uninstallation Script
# This script removes ChartMuseum from the edge-system namespace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests/chartmuseum"
NAMESPACE="${NAMESPACE:-edge-system}"
REPO_NAME="${REPO_NAME:-edge-charts}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

remove_helm_repo() {
    log_info "Removing Helm repository ${REPO_NAME}..."

    if helm repo list | grep -q "^${REPO_NAME}"; then
        helm repo remove "${REPO_NAME}"
        log_info "Helm repository removed"
    else
        log_warn "Helm repository ${REPO_NAME} not found, skipping"
    fi
}

delete_chartmuseum() {
    log_info "Deleting ChartMuseum from ${NAMESPACE}..."

    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        kubectl delete -k "${MANIFESTS_DIR}" --ignore-not-found=true
        log_info "ChartMuseum resources deleted"
    else
        log_warn "Namespace ${NAMESPACE} not found, skipping"
    fi
}

verify_cleanup() {
    log_info "Verifying cleanup..."

    if kubectl get deployment edge-museum -n "${NAMESPACE}" &> /dev/null 2>&1; then
        log_warn "Deployment still exists (may be terminating)"
    else
        log_info "✓ Deployment removed"
    fi

    if kubectl get service edge-museum -n "${NAMESPACE}" &> /dev/null 2>&1; then
        log_warn "Service still exists"
    else
        log_info "✓ Service removed"
    fi

    if helm repo list | grep -q "^${REPO_NAME}" 2>/dev/null; then
        log_warn "Helm repository still exists"
    else
        log_info "✓ Helm repository removed"
    fi
}

main() {
    log_info "Starting ChartMuseum uninstallation..."

    remove_helm_repo
    delete_chartmuseum
    verify_cleanup

    log_info "Uninstallation completed successfully!"
}

# Run main function
main "$@"
