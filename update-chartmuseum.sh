#!/bin/bash
# ChartMuseum 更新脚本
# 用于在更新 Charts 后重新构建并部署 ChartMuseum

set -e

# 配置
REGISTRY="${REGISTRY:-quanzhenglong.com/edge}"
TAG="${TAG:-main}"
MUSEUM_IMG="${REGISTRY}/edge-museum:${TAG}"
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==================== ChartMuseum 镜像更新流程 ===================="
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo "镜像: $MUSEUM_IMG"
echo "工作目录: $CHART_DIR"
echo "================================================================"

# 1. 打包所有 Charts（包括 edge-logs）
echo ""
echo "=== 步骤 1: 打包所有 Helm Charts ==="
cd "$CHART_DIR"
make package-charts

# 2. 构建 ChartMuseum 镜像
echo ""
echo "=== 步骤 2: 构建 ChartMuseum 镜像 ==="
make docker-build-museum MUSEUM_IMG="$MUSEUM_IMG"

# 3. 推送镜像
echo ""
echo "=== 步骤 3: 推送 ChartMuseum 镜像 ==="
make docker-push-museum MUSEUM_IMG="$MUSEUM_IMG"

# 4. 更新 ChartMuseum deployment
echo ""
echo "=== 步骤 4: 更新 ChartMuseum deployment ==="
kubectl set image deployment/chartmuseum chartmuseum="$MUSEUM_IMG" -n edge-system

echo ""
echo "✅ ChartMuseum 镜像更新完成！"
echo ""
echo "等待 ChartMuseum Pod 重启..."
kubectl rollout status deployment/chartmuseum -n edge-system

echo ""
echo "现在可以使用以下命令更新 edge-platform:"
echo "  helm upgrade edge-platform ./edge-controller --namespace edge-system --set global.imageRegistry=quanzhenglong.com"
