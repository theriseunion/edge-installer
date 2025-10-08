# OpenYurt 部署配置说明

## 概述

Edge Platform 基于 OpenYurt v1.6.0 提供边缘计算能力。本文档说明如何正确配置 OpenYurt 以确保边缘节点可以正常接入和运行。

## 关键配置：yurt-hub organizations 参数

### 问题背景

在边缘节点接入过程中，CNI 插件（如 Calico）需要通过 yurt-hub 代理访问 Kubernetes API Server。yurt-hub 为此生成 TLS 证书，但**必须在证书中包含正确的组织名称**才能通过 CNI 的证书验证。

**错误现象**：
- Pod 停留在 `ContainerCreating` 状态
- kubelet 日志显示：`TLS handshake timeout`
- CNI 插件无法通过 yurt-hub 访问 API

### 修复方案

yurt-hub 必须配置 `--hub-cert-organizations=system:nodes` 参数：

```bash
# 正确的 yurt-hub 启动命令应包含：
yurthub --v=2 \
  --bind-address=127.0.0.1 \
  --server-addr=https://172.16.0.30:6443 \
  --node-name=$(NODE_NAME) \
  --bootstrap-file=/var/lib/yurthub/bootstrap-hub.conf \
  --working-mode=edge \
  --namespace=kube-system \
  --hub-cert-organizations=system:nodes  # ← 关键参数
```

## 部署配置

### 1. Helm Chart 配置

确保 yurthub Helm chart 包含 organizations 参数：

```bash
# 安装或升级 yurthub
helm upgrade yurthub /path/to/yurthub-chart \
  -n kube-system \
  --set organizations="system:nodes" \
  --set kubernetesServerAddr="https://YOUR_API_SERVER:6443"
```

### 2. 验证配置

检查 YurtStaticSet 模板是否包含正确参数：

```bash
kubectl get yurtstaticset yurt-hub -n kube-system -o yaml | grep -A 15 "command:"
```

应该包含：
```yaml
- command:
  - yurthub
  - --v=2
  - --bind-address=127.0.0.1
  - --server-addr=https://172.16.0.30:6443
  - --node-name=$(NODE_NAME)
  - --bootstrap-file=/var/lib/yurthub/bootstrap-hub.conf
  - --working-mode=edge
  - --namespace=kube-system
  - --hub-cert-organizations=system:nodes  # ← 必须存在
```

### 3. 边缘节点加入脚本

更新节点加入脚本，确保生成的 yurtadm 命令包含 organizations 参数：

```bash
# 正确的 yurtadm join 命令
yurtadm join $API_SERVER \
  --node-name $NODE_NAME \
  --token $TOKEN \
  --node-type=edge \
  --cri-socket=$CRI_SOCKET \
  --yurthub-image=$YURTHUB_IMAGE \
  --hub-cert-organizations=system:nodes \  # ← 关键参数
  --discovery-token-unsafe-skip-ca-verification
```

## 验证部署

### 1. 检查 yurt-hub 证书

在边缘节点上验证证书包含正确的组织名：

```bash
# 在边缘节点执行
curl -k -v https://169.254.2.1:10268/apis/crd.projectcalico.org/v1/clusterinformations/default 2>&1 | grep subject

# 应该显示：
# subject: O=system:nodes; CN=system:node:NODE_NAME
```

### 2. 测试 CNI 功能

创建测试 Pod 验证网络功能：

```bash
kubectl run test-cni --image=busybox --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"EDGE_NODE_NAME"}}}' \
  -- sleep 3600

# 检查 Pod 状态
kubectl get pod test-cni -o wide
# 应该显示 Running 状态并分配了 IP
```

### 3. 检查节点状态

```bash
kubectl get nodes
# 边缘节点应该显示 Ready 状态
```

## 故障排除

### 问题：Pod 停留在 ContainerCreating

**症状**：
```bash
kubectl describe pod POD_NAME
# Events 显示：
# Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox: plugin type="calico" failed (add): error getting ClusterInformation: Get "https://169.254.2.1:10268/apis/crd.projectcalico.org/v1/clusterinformations/default": net/http: TLS handshake timeout
```

**解决方法**：
1. 检查 yurt-hub 是否包含 `--hub-cert-organizations=system:nodes` 参数
2. 如果缺少，按照上述步骤更新 Helm chart 或静态 Pod 配置
3. 重启 yurt-hub Pod 使配置生效

### 问题：节点状态 NotReady

**可能原因**：
- yurt-hub 服务未正常启动
- CNI 插件配置错误
- 网络连通性问题

**检查步骤**：
```bash
# 1. 检查 yurt-hub Pod 状态
kubectl get pod -n kube-system | grep yurt-hub

# 2. 检查 yurt-hub 日志
kubectl logs -n kube-system POD_NAME

# 3. 检查节点上的服务
ssh EDGE_NODE "systemctl status kubelet"
ssh EDGE_NODE "netstat -tlnp | grep 10261"
```

## 最佳实践

1. **自动化部署**：将 organizations 参数配置集成到部署脚本中
2. **版本控制**：确保 Helm values 文件包含此配置
3. **监控告警**：监控边缘节点状态和 Pod 创建成功率
4. **文档更新**：确保运维文档包含此配置要求

## 相关资源

- [OpenYurt 官方文档](https://openyurt.io/docs/)
- [yurt-hub 配置参考](https://openyurt.io/docs/core-concepts/yurthub/)
- [Edge Platform 节点接入 API](../edge-apiserver/pkg/oapis/infra/v1alpha1/)

---

**重要提醒**：此配置对边缘节点的正常运行至关重要。在任何 OpenYurt 升级或重新部署时，请确保保留此配置。