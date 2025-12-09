#!/bin/bash

# Edge Platform 清理脚本
# 用于完全清理 Edge Platform 相关资源，方便重新部署

set -e

echo "=== Edge Platform 清理脚本 ==="
echo ""

# 1. 删除所有 Component CRs (先删除CR，让controller完成清理工作)
echo "1. 删除 Component CRs..."
kubectl get components -A --no-headers | awk '{print $2 " -n " $1}' | while read name ns; do
    echo "  - 删除 Component: $name (namespace: $ns)"
    kubectl delete component $name -n $ns --ignore-not-found=true || true
done
echo ""

# 2. 等待资源清理完成
echo "2. 等待 Component 资源清理完成..."
sleep 10
echo ""

# 3. 删除所有 Helm releases
echo "3. 删除 Helm releases..."
helm list -A | grep -E "edge-|controller-" | awk '{print $1 " -n " $2}' | while read name ns; do
    echo "  - 删除 release: $name (namespace: $ns)"
    helm uninstall $name $ns || true
done
echo ""

# 4. 检查残留资源
echo "4. 检查残留资源..."
echo "  - Helm releases:"
helm list -A | grep -E "edge-|controller-" || echo "    (无残留 release)"
echo ""
echo "  - Component CRs:"
kubectl get components -A || echo "    (无残留 Component CR)"
echo ""

# 5. 清理 edge-system 命名空间中的部署
echo "5. 清理 edge-system 命名空间中的部署..."
kubectl delete deployment -n edge-system -l app.kubernetes.io/part-of=edge-platform --ignore-not-found=true || true
kubectl delete service -n edge-system -l app.kubernetes.io/part-of=edge-platform --ignore-not-found=true || true
kubectl delete configmap -n edge-system -l app.kubernetes.io/part-of=edge-platform --ignore-not-found=true || true
kubectl delete secret -n edge-system -l app.kubernetes.io/part-of=edge-platform --ignore-not-found=true || true
echo ""

# 6. 清理 observability-system 命名空间中的资源
echo "6. 清理 observability-system 命名空间中的资源..."
kubectl delete deployment -n observability-system -l app.kubernetes.io/part-of=edge-platform --ignore-not-found=true || true
kubectl delete service -n observability-system -l app.kubernetes.io/part-of=edge-platform --ignore-not-found=true || true
echo ""

# 7. 最终检查
echo "7. 最终检查..."
echo "  - edge-system 命名空间 Pods:"
kubectl get pods -n edge-system | grep -E "edge-|controller-" || echo "    (无残留 Pod)"
echo ""
echo "  - observability-system 命名空间 Pods:"
kubectl get pods -n observability-system | grep "edge-" || echo "    (无残留 Pod)"
echo ""

echo "=== 清理完成 ==="
echo "现在可以重新部署 Edge Platform"
