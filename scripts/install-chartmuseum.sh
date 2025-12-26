#!/usr/bin/env bash

set -euo pipefail

# ChartMuseum Installation Script
# This script deploys ChartMuseum to the edge-system namespace
# and configures Helm to use it as a chart repository

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests/chartmuseum"
NAMESPACE="${NAMESPACE:-edge-system}"
REPO_NAME="${REPO_NAME:-edge-charts}"
MUSEUM_IMAGE="${MUSEUM_IMAGE:-quanzhenglong.com/edge/edge-museum:main-qzl-v0.2-arm64}"

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

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install helm first."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    log_info "Prerequisites check passed"
}

create_namespace() {
    log_info "Ensuring namespace ${NAMESPACE} exists..."

    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        log_info "Namespace ${NAMESPACE} already exists"
    else
        kubectl create namespace "${NAMESPACE}"
        log_info "Created namespace ${NAMESPACE}"
    fi
}

deploy_chartmuseum() {
    log_info "Deploying ChartMuseum to ${NAMESPACE}..."

    # Update image in deployment if custom image is specified
    if [[ "${MUSEUM_IMAGE}" != "quanzhenglong.com/edge/edge-museum:main-qzl-v0.2-arm64" ]]; then
        log_info "Using custom image: ${MUSEUM_IMAGE}"
        kubectl set image deployment/edge-museum \
            chartmuseum="${MUSEUM_IMAGE}" \
            -n "${NAMESPACE}" --dry-run=client -o yaml | \
            kubectl apply -f -
    fi

    # Apply manifests using kustomize
    kubectl apply -k "${MANIFESTS_DIR}"

    log_info "Waiting for ChartMuseum to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/edge-museum -n "${NAMESPACE}"

    log_info "ChartMuseum deployed successfully"
}

configure_helm_repo() {
    log_info "Configuring Helm repository..."

    # Get ChartMuseum service endpoint
    MUSEUM_SERVICE="edge-museum.${NAMESPACE}.svc.cluster.local:8080"

    # Check if repository already exists
    if helm repo list | grep -q "^${REPO_NAME}"; then
        log_warn "Helm repository ${REPO_NAME} already exists, updating..."
        helm repo remove "${REPO_NAME}" || true
    fi

    # Add repository (using port-forward for initial setup)
    log_info "Setting up port-forward to ChartMuseum..."
    kubectl port-forward -n "${NAMESPACE}" svc/edge-museum 8080:8080 &
    PF_PID=$!

    # Wait for port-forward to be ready
    sleep 3

    # Add Helm repository
    if helm repo add "${REPO_NAME}" http://localhost:8080; then
        log_info "Helm repository ${REPO_NAME} added successfully"
    else
        log_error "Failed to add Helm repository"
        kill "${PF_PID}" 2>/dev/null || true
        exit 1
    fi

    # Kill port-forward
    kill "${PF_PID}" 2>/dev/null || true

    # Update repository
    helm repo update "${REPO_NAME}"

    log_info "Helm repository configured successfully"
    log_info "Repository URL (in-cluster): http://${MUSEUM_SERVICE}"
}

verify_installation() {
    log_info "Verifying ChartMuseum installation..."

    # Check deployment
    if kubectl get deployment edge-museum -n "${NAMESPACE}" &> /dev/null; then
        log_info "✓ Deployment exists"
    else
        log_error "✗ Deployment not found"
        return 1
    fi

    # Check service
    if kubectl get service edge-museum -n "${NAMESPACE}" &> /dev/null; then
        log_info "✓ Service exists"
    else
        log_error "✗ Service not found"
        return 1
    fi

    # Check pod status
    POD_STATUS=$(kubectl get pods -n "${NAMESPACE}" -l app=edge-museum -o jsonpath='{.items[0].status.phase}')
    if [[ "${POD_STATUS}" == "Running" ]]; then
        log_info "✓ Pod is running"
    else
        log_error "✗ Pod status: ${POD_STATUS}"
        return 1
    fi

    # List available charts
    log_info "Available charts in ${REPO_NAME}:"
    helm search repo "${REPO_NAME}/" || log_warn "No charts found (this is expected if ChartMuseum is empty)"

    log_info "ChartMuseum installation verified successfully"
}

print_usage_info() {
    cat <<EOF

${GREEN}ChartMuseum Installation Complete!${NC}

Next steps:
1. Configure Component Controller to use ChartMuseum:
   ${YELLOW}export CHART_REPO_NAME=${REPO_NAME}${NC}

2. In-cluster service URL:
   ${YELLOW}http://edge-museum.${NAMESPACE}.svc.cluster.local:8080${NC}

3. List available charts:
   ${YELLOW}helm search repo ${REPO_NAME}/${NC}

4. Create Component CR to install components:
   ${YELLOW}kubectl apply -f examples/component-apiserver.yaml${NC}

For more information, see:
- docs-installer/edge-museum-architecture.md
- docs-installer/component-installation-flow.md
EOF
}

main() {
    log_info "Starting ChartMuseum installation..."

    check_prerequisites
    create_namespace
    deploy_chartmuseum
    configure_helm_repo
    verify_installation
    print_usage_info

    log_info "Installation completed successfully!"
}

# Run main function
main "$@"
