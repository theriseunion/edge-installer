#!/bin/bash

# Edge 快速部署脚本
# 使用 Helm 直接部署三个组件

NAMESPACE=${NAMESPACE:-edge-system}
KUBECONFIG_PATH=${KUBECONFIG_PATH:-~/.kube/116.63.161.198.config}
REGISTRY=${REGISTRY:-quanzhenglong.com/edge}
TAG=${TAG:-main}

# 设置 kubeconfig
export KUBECONFIG=$KUBECONFIG_PATH

# 创建命名空间
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 部署 Controller
helm upgrade --install edge-controller ./edge-controller \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/edge-controller \
  --set image.tag=$TAG \
  --wait

# 部署 API Server
helm upgrade --install edge-apiserver ./edge-apiserver \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/edge-apiserver \
  --set image.tag=$TAG \
  --wait

# 部署 Console
helm upgrade --install edge-console ./edge-console \
  --namespace $NAMESPACE \
  --set image.repository=$REGISTRY/edge-console \
  --set image.tag=$TAG \
  --set env[0].name=NEXT_PUBLIC_API_BASE_URL \
  --set env[0].value=http://edge-apiserver:8080 \
  --wait

echo "部署完成！"
echo "查看 Pod 状态："
kubectl get pods -n $NAMESPACE