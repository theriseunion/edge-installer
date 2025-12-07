#!/bin/bash
# ===================================================================
# 第一阶段: 通过Helm直接安装charts到ORB K8s集群
# ===================================================================

set -e

# 配置
KUBECONTEXT="orbstack"
NAMESPACE="edge-system"
MONITORING_NAMESPACE="observability-system"

# 镜像配置 (使用本地编译的镜像)
REGISTRY="quanzhenglong.com/edge"
TAG="main-local"
PULL_POLICY="IfNotPresent"

# Chart路径
CHART_DIR="/Users/neov/src/github.com/edgekeel/apiserver/edge-installer"

echo "========================================="
echo "第一阶段: Helm直接安装 (ORB集群)"
echo "========================================="
echo "Kubernetes Context: $KUBECONTEXT"
echo "Namespace: $NAMESPACE"
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo ""

# 步骤1: 清理集群
echo "步骤1: 清理ORB集群..."

# 1.1 卸载所有 Helm releases
echo "卸载所有 Helm releases..."
helm --kube-context=$KUBECONTEXT list -A --short | xargs -I {} helm --kube-context=$KUBECONTEXT uninstall {} || true

# 1.2 删除集群级别的资源（先删除这些，避免阻塞 namespace 删除）
echo "删除 ClusterRole 和 ClusterRoleBinding..."
kubectl --context=$KUBECONTEXT delete clusterrole controller edge-controller edge-apiserver --ignore-not-found=true || true
kubectl --context=$KUBECONTEXT delete clusterrolebinding controller edge-controller edge-apiserver --ignore-not-found=true || true

# 1.3 删除 namespaces（不等待）
echo "删除 namespaces..."
kubectl --context=$KUBECONTEXT delete namespace $NAMESPACE --ignore-not-found=true --wait=false || true
kubectl --context=$KUBECONTEXT delete namespace $MONITORING_NAMESPACE --ignore-not-found=true --wait=false || true

# 1.4 删除所有 theriseunion CRDs（不等待）
echo "删除现有 CRDs..."
kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | xargs -I {} kubectl --context=$KUBECONTEXT delete {} --ignore-not-found=true --wait=false || true

# 1.5 等待 CRDs 完全删除
echo "等待 CRDs 完全删除（最多120秒）..."
for i in {1..24}; do
  CRD_COUNT=$(kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | wc -l | tr -d ' ')
  if [ "$CRD_COUNT" -eq "0" ]; then
    echo "CRDs 已删除"
    break
  fi
  echo "等待 CRDs 删除... 还剩 $CRD_COUNT 个 ($i/24)"
  sleep 5
done

# 1.6 等待 namespaces 完全删除
echo "等待 namespaces 完全删除（最多120秒）..."
for i in {1..24}; do
  if ! kubectl --context=$KUBECONTEXT get namespace $NAMESPACE &>/dev/null && \
     ! kubectl --context=$KUBECONTEXT get namespace $MONITORING_NAMESPACE &>/dev/null; then
    echo "Namespaces 已删除"
    break
  fi
  echo "等待中... ($i/24)"
  sleep 5
done

# 1.7 强制删除残留的 finalizers（如果namespace还在）
if kubectl --context=$KUBECONTEXT get namespace $NAMESPACE &>/dev/null; then
  echo "强制删除 $NAMESPACE 的 finalizers..."
  kubectl --context=$KUBECONTEXT patch namespace $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge || true
fi
if kubectl --context=$KUBECONTEXT get namespace $MONITORING_NAMESPACE &>/dev/null; then
  echo "强制删除 $MONITORING_NAMESPACE 的 finalizers..."
  kubectl --context=$KUBECONTEXT patch namespace $MONITORING_NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge || true
fi

echo "最终等待5秒..."
sleep 5

# 1.8 验证所有 CRD 都已删除
echo ""
echo "验证 CRD 删除结果..."
CRD_COUNT=$(kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | wc -l | tr -d ' ')
if [ "$CRD_COUNT" -eq "0" ]; then
  echo "✓ 所有 CRD 已成功删除"
else
  echo "⚠ 警告：还有 $CRD_COUNT 个 CRD 未删除"
  kubectl --context=$KUBECONTEXT get crd | grep theriseunion
fi

# 步骤2: 创建namespace
echo ""
echo "步骤2: 创建namespace..."
kubectl --context=$KUBECONTEXT create namespace $NAMESPACE
kubectl --context=$KUBECONTEXT create namespace $MONITORING_NAMESPACE

# 步骤3: 安装edge-controller (包含所有CRDs)
echo ""
echo "步骤3: 安装edge-controller..."
helm --kube-context=$KUBECONTEXT install edge-controller $CHART_DIR/edge-controller \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/controller \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait --timeout=5m

echo "等待controller就绪..."
kubectl --context=$KUBECONTEXT wait --for=condition=available deployment/controller \
  -n $NAMESPACE --timeout=120s

# 3.1 验证 CRD 安装结果
echo ""
echo "验证 CRD 安装结果..."
CRD_COUNT=$(kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | wc -l | tr -d ' ')
EXPECTED_CRD_COUNT=15

if [ "$CRD_COUNT" -eq "$EXPECTED_CRD_COUNT" ]; then
  echo "✓ 所有 $EXPECTED_CRD_COUNT 个 CRD 已成功安装"
else
  echo "⚠ 警告：期望 $EXPECTED_CRD_COUNT 个 CRD，实际安装了 $CRD_COUNT 个"
  echo ""
  echo "已安装的 CRD："
  kubectl --context=$KUBECONTEXT get crd | grep theriseunion
  echo ""

  # 检查缺失的关键 CRD
  echo "检查关键 CRD..."
  MISSING_CRDS=""

  if ! kubectl --context=$KUBECONTEXT get crd clusters.scope.theriseunion.io &>/dev/null; then
    echo "✗ 缺失: clusters.scope.theriseunion.io"
    MISSING_CRDS="$MISSING_CRDS clusters"
  fi

  if ! kubectl --context=$KUBECONTEXT get crd users.iam.theriseunion.io &>/dev/null; then
    echo "✗ 缺失: users.iam.theriseunion.io"
    MISSING_CRDS="$MISSING_CRDS users"
  fi

  if [ -n "$MISSING_CRDS" ]; then
    echo ""
    echo "正在手动安装缺失的 CRD..."

    if echo "$MISSING_CRDS" | grep -q "clusters"; then
      echo "安装 clusters CRD..."
      kubectl --context=$KUBECONTEXT apply -f $CHART_DIR/edge-controller/crds/scope.theriseunion.io_clusters.yaml
    fi

    if echo "$MISSING_CRDS" | grep -q "users"; then
      echo "安装 users CRD..."
      kubectl --context=$KUBECONTEXT apply -f $CHART_DIR/edge-controller/crds/iam.theriseunion.io_users.yaml
    fi

    # 再次验证
    CRD_COUNT=$(kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | wc -l | tr -d ' ')
    echo "修复后的 CRD 数量: $CRD_COUNT"
  fi
fi

# 步骤4: 安装edge-apiserver
echo ""
echo "步骤4: 安装edge-apiserver..."
helm --kube-context=$KUBECONTEXT install edge-apiserver $CHART_DIR/edge-apiserver \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/apiserver \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait --timeout=5m

echo "等待apiserver就绪..."
kubectl --context=$KUBECONTEXT wait --for=condition=available deployment/apiserver \
  -n $NAMESPACE --timeout=120s

# 步骤5: 安装edge-console
echo ""
echo "步骤5: 安装edge-console..."
helm --kube-context=$KUBECONTEXT install edge-console $CHART_DIR/edge-console \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/console \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --wait --timeout=5m

echo "等待console就绪..."
kubectl --context=$KUBECONTEXT wait --for=condition=available deployment/console \
  -n $NAMESPACE --timeout=120s

# 步骤6: 安装edge-monitoring
echo ""
echo "步骤6: 安装edge-monitoring..."
helm --kube-context=$KUBECONTEXT install edge-monitoring $CHART_DIR/edge-monitoring \
  --namespace $MONITORING_NAMESPACE \
  --set monitoringService.image.repository=$REGISTRY/monitoring-service \
  --set monitoringService.image.tag=$TAG \
  --set monitoringService.image.pullPolicy=$PULL_POLICY \
  --wait --timeout=5m

# 步骤7: 验证安装
echo ""
echo "========================================="
echo "安装完成! 验证状态..."
echo "========================================="
echo ""
echo "Namespaces:"
kubectl --context=$KUBECONTEXT get namespaces | grep -E "(edge-system|observability-system)"

echo ""
echo "Pods in edge-system:"
kubectl --context=$KUBECONTEXT get pods -n $NAMESPACE

echo ""
echo "Pods in observability-system:"
kubectl --context=$KUBECONTEXT get pods -n $MONITORING_NAMESPACE

echo ""
echo "Helm Releases:"
helm --kube-context=$KUBECONTEXT list -A | grep edge

echo ""
echo "CRDs:"
kubectl --context=$KUBECONTEXT get crd | grep theriseunion | wc -l
echo "个theriseunion CRDs"

echo ""
echo "========================================="
echo "第一阶段安装完成!"
echo "========================================="
echo ""
echo "如果出现问题,使用以下命令查看日志:"
echo "kubectl --context=$KUBECONTEXT logs -n $NAMESPACE deployment/edge-controller"
echo "kubectl --context=$KUBECONTEXT logs -n $NAMESPACE deployment/edge-apiserver"
echo "kubectl --context=$KUBECONTEXT logs -n $NAMESPACE deployment/edge-console"
