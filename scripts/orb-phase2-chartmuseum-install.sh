#!/bin/bash
# ===================================================================
# 第二阶段: 通过 ChartMuseum + Controller + Component CR 安装
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

# 路径
INSTALLER_DIR="/Users/neov/src/github.com/edgekeel/apiserver/edge-installer"
CHART_DIR="$INSTALLER_DIR"
MANIFESTS_DIR="$INSTALLER_DIR/manifests/chartmuseum"

echo "========================================="
echo "第二阶段: ChartMuseum + Controller 安装"
echo "========================================="
echo "Kubernetes Context: $KUBECONTEXT"
echo "Namespace: $NAMESPACE"
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo ""

# ===================================================================
# 步骤1: 清理集群 (正确顺序: Component CR -> Helm -> Namespace -> CRD)
# ===================================================================
echo "步骤1: 清理ORB集群..."

# 1.1 删除 Component CRs (先删除,让运行中的 Controller 处理 finalizers)
echo "1.1 删除 Component CRs..."
kubectl --context=$KUBECONTEXT delete component --all -n $NAMESPACE 2>/dev/null || true
kubectl --context=$KUBECONTEXT delete component --all -n $MONITORING_NAMESPACE 2>/dev/null || true

# 1.2 等待 Component CRs 完全删除 (Controller 处理 finalizers)
echo "1.2 等待 Component CRs 完全删除..."
for i in {1..24}; do
  COMPONENT_COUNT=$(kubectl --context=$KUBECONTEXT get components -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$COMPONENT_COUNT" -eq "0" ]; then
    echo "✓ 所有 Component CR 已删除"
    break
  fi
  echo "等待 Component CR 删除... 还剩 $COMPONENT_COUNT 个 ($i/24)"
  sleep 5
done

# 1.3 卸载所有 edge 相关 Helm releases (Component CR 删除后再卸载 Controller)
echo "1.3 卸载 Helm releases..."
helm --kube-context=$KUBECONTEXT uninstall edge-controller -n $NAMESPACE 2>/dev/null || true
helm --kube-context=$KUBECONTEXT uninstall edge-apiserver -n $NAMESPACE 2>/dev/null || true
helm --kube-context=$KUBECONTEXT uninstall edge-console -n $NAMESPACE 2>/dev/null || true
helm --kube-context=$KUBECONTEXT uninstall edge-monitoring -n $MONITORING_NAMESPACE 2>/dev/null || true

# 1.4 删除 ClusterRole 和 ClusterRoleBinding
echo "1.4 删除 ClusterRole/ClusterRoleBinding..."
kubectl --context=$KUBECONTEXT delete clusterrole controller apiserver console --ignore-not-found=true 2>/dev/null || true
kubectl --context=$KUBECONTEXT delete clusterrolebinding controller apiserver console --ignore-not-found=true 2>/dev/null || true

# 1.5 删除 namespaces
echo "1.5 删除 namespaces..."
kubectl --context=$KUBECONTEXT delete namespace $NAMESPACE --ignore-not-found=true --wait=false 2>/dev/null || true
kubectl --context=$KUBECONTEXT delete namespace $MONITORING_NAMESPACE --ignore-not-found=true --wait=false 2>/dev/null || true

# 1.6 等待 namespaces 完全删除
echo "1.6 等待 namespaces 完全删除..."
for i in {1..24}; do
  if ! kubectl --context=$KUBECONTEXT get namespace $NAMESPACE &>/dev/null && \
     ! kubectl --context=$KUBECONTEXT get namespace $MONITORING_NAMESPACE &>/dev/null; then
    echo "✓ Namespaces 已删除"
    break
  fi
  echo "等待中... ($i/24)"
  sleep 5
done

# 1.7 删除所有 theriseunion CRDs (在 namespace 删除后)
echo "1.7 删除所有 theriseunion CRDs..."
kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | xargs -I {} kubectl --context=$KUBECONTEXT delete {} --ignore-not-found=true --wait=false 2>/dev/null || true

# 1.8 等待 CRDs 完全删除
echo "1.8 等待 CRDs 完全删除..."
for i in {1..24}; do
  CRD_COUNT=$(kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | wc -l | tr -d ' ')
  if [ "$CRD_COUNT" -eq "0" ]; then
    echo "✓ 所有 CRD 已删除"
    break
  fi
  echo "等待 CRD 删除... 还剩 $CRD_COUNT 个 ($i/24)"
  sleep 5
done

sleep 3

# ===================================================================
# 步骤2: 创建 namespaces
# ===================================================================
echo ""
echo "步骤2: 创建namespaces..."
kubectl --context=$KUBECONTEXT create namespace $NAMESPACE
kubectl --context=$KUBECONTEXT create namespace $MONITORING_NAMESPACE

# ===================================================================
# 步骤3: 部署 ChartMuseum
# ===================================================================
echo ""
echo "步骤3: 部署 ChartMuseum..."

# 更新 deployment.yaml 中的镜像
cat > /tmp/chartmuseum-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-museum
  namespace: $NAMESPACE
  labels:
    app: edge-museum
spec:
  replicas: 1
  selector:
    matchLabels:
      app: edge-museum
  template:
    metadata:
      labels:
        app: edge-museum
    spec:
      containers:
      - name: chartmuseum
        image: $REGISTRY/edge-museum:$TAG
        imagePullPolicy: $PULL_POLICY
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: STORAGE
          value: "local"
        - name: STORAGE_LOCAL_ROOTDIR
          value: "/charts"
        - name: PORT
          value: "8080"
        - name: DEBUG
          value: "true"
        - name: DISABLE_API
          value: "false"
        - name: ALLOW_OVERWRITE
          value: "true"
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: edge-museum
  namespace: $NAMESPACE
  labels:
    app: edge-museum
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: edge-museum
EOF

kubectl --context=$KUBECONTEXT apply -f /tmp/chartmuseum-deployment.yaml

echo "等待 ChartMuseum 就绪..."
kubectl --context=$KUBECONTEXT wait --for=condition=available deployment/edge-museum \
  -n $NAMESPACE --timeout=120s

# 验证 ChartMuseum
echo "验证 ChartMuseum 中的 Charts..."
kubectl --context=$KUBECONTEXT exec -n $NAMESPACE deployment/edge-museum -- ls -la /charts/ 2>/dev/null || echo "无法列出 charts"

# ===================================================================
# 步骤4: 安装 Controller (包含 CRDs)
# ===================================================================
echo ""
echo "步骤4: 安装 Controller (包含 CRDs)..."
helm --kube-context=$KUBECONTEXT install edge-controller $CHART_DIR/edge-controller \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/controller \
  --set image.tag=$TAG \
  --set image.pullPolicy=$PULL_POLICY \
  --set chartRepository.url=http://edge-museum.$NAMESPACE.svc:8080 \
  --set chartRepository.name=edge-charts \
  --wait --timeout=5m

echo "等待 Controller 就绪..."
kubectl --context=$KUBECONTEXT wait --for=condition=available deployment/controller \
  -n $NAMESPACE --timeout=120s

# 验证 CRDs
echo ""
echo "验证 CRD 安装结果..."
CRD_COUNT=$(kubectl --context=$KUBECONTEXT get crd -o name 2>/dev/null | grep theriseunion | wc -l | tr -d ' ')
EXPECTED_CRD_COUNT=15

if [ "$CRD_COUNT" -eq "$EXPECTED_CRD_COUNT" ]; then
  echo "✓ 所有 $EXPECTED_CRD_COUNT 个 CRD 已成功安装"
else
  echo "⚠ 警告:期望 $EXPECTED_CRD_COUNT 个 CRD,实际安装了 $CRD_COUNT 个"
  echo ""
  echo "已安装的 CRD:"
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

    # 重启 controller 让它重新加载 CRDs
    echo "重启 controller 以重新加载 CRDs..."
    kubectl --context=$KUBECONTEXT rollout restart deployment/controller -n $NAMESPACE
    kubectl --context=$KUBECONTEXT wait --for=condition=available deployment/controller -n $NAMESPACE --timeout=120s
  fi
fi

# ===================================================================
# 步骤5: 创建 Component CRs
# ===================================================================
echo ""
echo "步骤5: 创建 Component CRs..."

# Get chart version from ChartMuseum
CHART_VERSION="0.1.0"
echo "Using chart version: $CHART_VERSION"

# APIServer Component
cat <<EOF | kubectl --context=$KUBECONTEXT apply -f -
apiVersion: ext.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: edge-apiserver
  namespace: $NAMESPACE
spec:
  type: apiserver
  enabled: true
  version: "$CHART_VERSION"
  chart:
    name: edge-apiserver
    namespace: $NAMESPACE
    releaseName: edge-apiserver
  values:
    image:
      repository: $REGISTRY/apiserver
      tag: $TAG
      pullPolicy: $PULL_POLICY
EOF

# Console Component
cat <<EOF | kubectl --context=$KUBECONTEXT apply -f -
apiVersion: ext.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: edge-console
  namespace: $NAMESPACE
spec:
  type: console
  enabled: true
  version: "$CHART_VERSION"
  chart:
    name: edge-console
    namespace: $NAMESPACE
    releaseName: edge-console
  values:
    image:
      repository: $REGISTRY/console
      tag: $TAG
      pullPolicy: $PULL_POLICY
EOF

# Monitoring Component
cat <<EOF | kubectl --context=$KUBECONTEXT apply -f -
apiVersion: ext.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: edge-monitoring
  namespace: $MONITORING_NAMESPACE
spec:
  type: monitoring
  enabled: true
  version: "$CHART_VERSION"
  chart:
    name: edge-monitoring
    namespace: $MONITORING_NAMESPACE
    releaseName: edge-monitoring
  values:
    monitoringService:
      image:
        repository: $REGISTRY/monitoring-service
        tag: $TAG
        pullPolicy: $PULL_POLICY
EOF

echo "Component CRs 已创建"
kubectl --context=$KUBECONTEXT get components -A

# ===================================================================
# 步骤6: 等待 Controller 处理 Component CRs
# ===================================================================
echo ""
echo "步骤6: 等待 Controller 处理 Component CRs (最多5分钟)..."

for i in {1..30}; do
  INSTALLED_COUNT=$(kubectl --context=$KUBECONTEXT get components -A -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c "Installed" || echo "0")
  echo "已安装: $INSTALLED_COUNT/3 个组件 ($i/30)"

  if [ "$INSTALLED_COUNT" -ge 3 ]; then
    echo "所有组件安装完成!"
    break
  fi

  sleep 10
done

# ===================================================================
# 步骤7: 验证安装
# ===================================================================
echo ""
echo "========================================="
echo "安装完成! 验证状态..."
echo "========================================="

echo ""
echo "Component 状态:"
kubectl --context=$KUBECONTEXT get components -A

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
echo "========================================="
echo "第二阶段安装完成!"
echo "========================================="
echo ""
echo "查看日志:"
echo "kubectl --context=$KUBECONTEXT logs -n $NAMESPACE deployment/controller"
echo "kubectl --context=$KUBECONTEXT logs -n $NAMESPACE deployment/apiserver"
echo ""
