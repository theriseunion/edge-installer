#!/bin/bash

# Edge Platform 更新脚本
# 支持 CRD 更新、前置依赖安装和主组件升级

set -e

# 默认配置
NAMESPACE=${NAMESPACE:-edge-system}
COMPONENT=${COMPONENT:-apiserver}  # 可选: apiserver, controller, console
TAG=${TAG:-$(echo "nightly-$(TZ=Asia/Shanghai date +'%Y%m%d')")}
DEV_MODE=${DEV_MODE:-true}
SKIP_CRDS=${SKIP_CRDS:-false}
FORCE=${FORCE:-false}

echo "==================== Edge Platform 更新 ===================="
echo "命名空间: $NAMESPACE"
echo "更新组件: $COMPONENT"
echo "镜像标签: $TAG"
echo "开发模式: $DEV_MODE"
echo "跳过 CRD: $SKIP_CRDS"
echo "强制升级: $FORCE"
echo "===================================================================="

# 用户确认
echo ""
read -p "确认以上参数并开始更新？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ 用户取消更新"
    exit 1
fi

echo ""
echo "✅ 开始更新 Edge Platform..."
echo ""

# 设置 Chart 路径
case $COMPONENT in
    "apiserver")
        CHART_PATH="./edge-apiserver"
        RELEASE_NAME="edge-apiserver"
        ;;
    "controller")
        CHART_PATH="./edge-controller"
        RELEASE_NAME="edge-controller"
        ;;
    "console")
        CHART_PATH="./edge-console"
        RELEASE_NAME="edge-console"
        ;;
    *)
        echo "❌ 错误：不支持的组件 $COMPONENT"
        echo "支持的组件: apiserver, controller, console"
        exit 1
        ;;
esac

echo "使用 Chart 路径: $CHART_PATH"
echo "使用 Release 名称: $RELEASE_NAME"

# 1. 安装前置依赖（如果有）
echo "安装前置依赖..."
if [ -f "$CHART_PATH/README.md" ]; then
    echo "执行 Chart README 中的前置命令..."
    helm show readme "$CHART_PATH" | awk '/```bash/{flag=1; next} /```/{flag=0} flag' | bash - || {
        echo "⚠️  README 前置命令执行失败或不存在，继续执行..."
    }
fi

# 2. 更新 CRDs
if [ "$SKIP_CRDS" = "false" ]; then
    echo "更新 CRDs..."
    helm show crds "$CHART_PATH" | kubectl apply -f - || {
        echo "❌ CRD 更新失败"
        exit 1
    }
    echo "✅ CRDs 更新完成"
else
    echo "跳过 CRD 更新"
fi

# 3. 准备升级参数
HELM_ARGS=""
if [ "$FORCE" = "true" ]; then
    HELM_ARGS="$HELM_ARGS --force"
fi
HELM_ARGS="$HELM_ARGS --skip-crds --debug --wait"

# 设置 Helm values
case $COMPONENT in
    "apiserver")
        HELM_VALUES="--set devMode=$DEV_MODE --set global.tag=$TAG"
        ;;
    "controller")
        HELM_VALUES="--set image.tag=$TAG"
        ;;
    "console")
        HELM_VALUES="--set image.tag=$TAG --set env[0].name=NEXT_PUBLIC_API_BASE_URL --set env[0].value=http://apiserver:8080"
        ;;
esac

# 检查是否存在现有 release
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    echo "检测到现有 release，执行升级..."
    UPGRADE_CMD="helm upgrade -n $NAMESPACE $RELEASE_NAME $CHART_PATH $HELM_VALUES $HELM_ARGS"
else
    echo "未检测到现有 release，执行安装..."
    UPGRADE_CMD="helm install -n $NAMESPACE $RELEASE_NAME $CHART_PATH $HELM_VALUES $HELM_ARGS"
fi

echo "执行命令: $UPGRADE_CMD"
echo ""

# 4. 执行升级/安装
eval "$UPGRADE_CMD" || {
    echo "❌ 升级失败"
    echo "请检查："
    echo "1. Chart 路径是否正确: $CHART_PATH"
    echo "2. 集群连接是否正常"
    echo "3. 命名空间是否存在: $NAMESPACE"
    exit 1
}

echo ""
echo "✅ Edge Platform 更新完成！"
echo ""
echo "验证部署状态："
echo "kubectl get pods -n $NAMESPACE"
echo "kubectl get svc -n $NAMESPACE"
echo ""
echo "查看详细状态："
echo "helm status -n $NAMESPACE $RELEASE_NAME"