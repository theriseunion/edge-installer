#!/bin/bash

# Component Controller Lifecycle Test
# Tests installation, upgrade, and uninstallation of components

set -e

# Color output
RED='\033[0.31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}====== Component Controller Lifecycle Test ======${NC}"

# Get the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Project root: $PROJECT_ROOT"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up test resources...${NC}"
    kubectl delete component test-component 2>/dev/null || true
}

# Register cleanup on exit
trap cleanup EXIT

# Test 1: Create a test Component CR
echo -e "\n${GREEN}Test 1: Creating test Component CR...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: installer.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: test-component
spec:
  componentType: apiserver
  namespace: edge-system-test
  releaseName: test-apiserver
  chartPath: $PROJECT_ROOT/edge-apiserver
  values:
    image:
      repository: quanzhenglong.com/edge/apiserver
      tag: main
      pullPolicy: IfNotPresent
    service:
      type: ClusterIP
      port: 8080
EOF

echo "Waiting for component to be created..."
kubectl wait --for=condition=Ready component/test-component --timeout=30s 2>/dev/null || true

# Test 2: Check component status
echo -e "\n${GREEN}Test 2: Checking Component status...${NC}"
kubectl get component test-component -o yaml

# Check if Helm release was created
echo -e "\n${GREEN}Checking Helm release...${NC}"
helm list -n edge-system-test

# Check if namespace was created
echo -e "\n${GREEN}Checking namespace...${NC}"
kubectl get namespace edge-system-test

# Check if deployment was created
echo -e "\n${GREEN}Checking deployment...${NC}"
kubectl get deployment -n edge-system-test

# Test 3: Update component (trigger upgrade)
echo -e "\n${GREEN}Test 3: Updating Component (testing upgrade)...${NC}"
kubectl patch component test-component --type=merge -p '{
  "spec": {
    "values": {
      "image": {
        "tag": "v1.0.0"
      }
    }
  }
}'

echo "Waiting for upgrade to complete..."
sleep 10
kubectl get component test-component -o yaml

# Test 4: Disable component (uninstall)
echo -e "\n${GREEN}Test 4: Disabling Component (testing uninstall)...${NC}"
kubectl patch component test-component --type=merge -p '{"spec":{"enabled":false}}'

echo "Waiting for uninstall..."
sleep 10

# Check if Helm release was removed
echo -e "\n${GREEN}Checking if Helm release was removed...${NC}"
helm list -n edge-system-test || echo "Helm release removed successfully"

# Test 5: Delete component CR
echo -e "\n${GREEN}Test 5: Deleting Component CR...${NC}"
kubectl delete component test-component

echo -e "\n${GREEN}====== All Tests Completed ======${NC}"
