#!/bin/bash

# 卸载 OpenYurt 1.6 脚本
# 使用方法: ./uninstall-openyurt-1.6.sh [kubeconfig-path]

KUBECONFIG_PATH=${1:-~/.kube/192.168.1.102.config}

echo "==================== 卸载 OpenYurt 1.6 ===================="
echo "使用 kubeconfig: $KUBECONFIG_PATH"
echo ""

export KUBECONFIG=$KUBECONFIG_PATH

# 1. 卸载 yurthub (Helm release)
echo "1. 卸载 yurthub Helm release..."
helm uninstall yurthub -n kube-system || echo "⚠️  yurthub release 不存在或已卸载"

# 2. 卸载 yurt-manager (Helm release)
echo "2. 卸载 yurt-manager Helm release..."
helm uninstall yurt-manager -n kube-system || echo "⚠️  yurt-manager release 不存在或已卸载"

# 3. 卸载 openyurt-config (如果存在)
echo "3. 卸载 openyurt-config Helm release..."
helm uninstall openyurt-config -n kube-system || echo "⚠️  openyurt-config release 不存在或已卸载"

# 4. 删除 ConfigMap
echo "4. 删除 yurt-static-set-yurt-hub ConfigMap..."
kubectl delete configmap yurt-static-set-yurt-hub -n kube-system --ignore-not-found=true

# 5. 删除 YurtStaticSet 资源
echo "5. 删除 YurtStaticSet 资源..."
kubectl delete yurtstaticset --all -n kube-system --ignore-not-found=true

# 6. 清理 CRDs (可选,谨慎操作)
echo "6. 是否删除 OpenYurt CRDs? (y/N)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  echo "删除 OpenYurt CRDs..."
  kubectl delete crd yurtstaticsets.apps.openyurt.io --ignore-not-found=true
  kubectl delete crd yurtappdaemons.apps.openyurt.io --ignore-not-found=true
  kubectl delete crd yurtappsets.apps.openyurt.io --ignore-not-found=true
  kubectl delete crd yurtappoverriders.apps.openyurt.io --ignore-not-found=true
  kubectl delete crd nodepools.apps.openyurt.io --ignore-not-found=true
else
  echo "跳过 CRD 删除"
fi

echo ""
echo "✅ OpenYurt 1.6 卸载完成"
echo ""
echo "验证卸载结果:"
echo "kubectl get pods -n kube-system | grep yurt"
kubectl get pods -n kube-system | grep yurt || echo "无 yurt 相关 pods"
