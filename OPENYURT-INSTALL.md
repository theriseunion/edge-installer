# OpenYurt 安装指南

## 概述

本文档说明如何使用官方 Helm charts 在 Kubernetes 集群中安装 OpenYurt。

OpenYurt 是一个云原生边缘计算框架，通过扩展 Kubernetes 的能力，使其能够无缝地支持边缘场景。

## 前置要求

- Kubernetes 集群 v1.20+
- Helm 3.x
- kubectl 已配置并能访问集群

## 安装方式

### 方式一：使用 deploy.sh 自动安装（推荐）

最简单的方式是使用我们提供的 `deploy.sh` 脚本：

```bash
# 设置环境变量
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://192.168.1.102:6443  # 替换为你的 API Server 地址

# 运行部署脚本
./deploy.sh
```

完整示例：

```bash
# 在 192.168.1.102 集群上安装 Edge Platform + OpenYurt
export KUBECONFIG_PATH=~/.kube/192.168.1.102.config
export NAMESPACE=edge-system
export REGISTRY=quanzhenglong.com/edge
export TAG=main
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://192.168.1.102:6443

./deploy.sh
```

### 方式二：手动安装

如果你需要更精细的控制，可以手动安装 OpenYurt 组件。

#### 1. 添加 OpenYurt Helm 仓库

```bash
helm repo add openyurt https://openyurtio.github.io/openyurt-helm
helm repo update
```

#### 2. 安装 yurt-manager

yurt-manager 是 OpenYurt 的核心控制器，负责管理边缘节点和边缘应用。

```bash
helm upgrade --install yurt-manager openyurt/yurt-manager \
  --namespace kube-system \
  --wait \
  --timeout 5m
```

验证安装：

```bash
kubectl get pods -n kube-system | grep yurt-manager
# 应该显示 yurt-manager pod 处于 Running 状态
```

#### 3. 安装 yurthub

yurthub 提供边缘节点的静态 Pod 配置。

```bash
# 替换为你的 API Server 地址
export API_SERVER=https://192.168.1.102:6443

helm upgrade --install yurthub openyurt/yurthub \
  --namespace kube-system \
  --set kubernetesServerAddr=$API_SERVER \
  --wait \
  --timeout 5m
```

验证安装：

```bash
# 检查 YurtStaticSet 资源
kubectl get yurtstaticset -n kube-system

# 检查生成的 ConfigMap
kubectl get configmap yurt-static-set-yurt-hub -n kube-system
kubectl describe configmap yurt-static-set-yurt-hub -n kube-system
```

#### 4. （可选）安装 raven-agent

raven-agent 提供边缘节点之间的网络通信能力。

```bash
helm upgrade --install raven-agent openyurt/raven-agent \
  --namespace kube-system \
  --wait \
  --timeout 5m
```

## 验证安装

### 1. 检查 OpenYurt 组件状态

```bash
# 查看所有 yurt 相关的 Pods
kubectl get pods -n kube-system | grep yurt

# 预期输出：
# yurt-manager-xxx    1/1     Running   0          5m
```

### 2. 检查 CRDs

```bash
# 查看 OpenYurt 的 CRD
kubectl get crd | grep openyurt

# 预期输出应包含：
# yurtstaticsets.apps.openyurt.io
```

### 3. 检查 YurtStaticSet

```bash
kubectl get yurtstaticset -n kube-system

# 预期输出：
# NAME             AGE   TOTAL   READY   UPGRADED
# yurt-hub         1m    0       0       0
# yurt-hub-cloud   1m    0       0       0
```

### 4. 检查边缘配置 ConfigMap

```bash
kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml | grep -A 10 "command:"

# 应该看到包含 --server-addr 和 --hub-cert-organizations 的配置
```

## 配置 Edge Platform 使用 OpenYurt

安装 OpenYurt 后，需要配置 Edge Platform 的集群使用 OpenYurt 作为边缘运行时。

### 通过 Web Console 配置

1. 访问 Edge Platform Console
2. 进入 **集群管理** → 选择集群 → **基本信息**
3. 找到 **边缘运行时** 字段，点击编辑图标
4. 选择 **openyurt** 并保存

### 通过 kubectl 配置

```bash
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt \
  --overwrite
```

验证配置：

```bash
kubectl get cluster host -o yaml | grep edge-runtime
# 输出：cluster.theriseunion.io/edge-runtime: openyurt
```

## 生成边缘节点加入命令

配置完成后，可以通过 Edge Platform API 生成边缘节点的加入命令：

```bash
curl "http://localhost:8080/oapis/infra.theriseunion.io/v1alpha1/join-token?nodeName=edge-node-01"
```

成功响应示例：

```json
{
  "apiVersion": "infra.theriseunion.io/v1alpha1",
  "kind": "JoinToken",
  "metadata": {
    "cluster": "host",
    "runtime": "openyurt"
  },
  "spec": {
    "token": "abcdef.0123456789abcdef",
    "command": "echo \"<base64-encoded-script>\" | base64 -d | bash",
    "expiresAt": "2025-10-13T10:00:00Z"
  }
}
```

## 卸载 OpenYurt

如果需要卸载 OpenYurt：

```bash
# 卸载 yurthub
helm uninstall yurthub -n kube-system

# 卸载 yurt-manager
helm uninstall yurt-manager -n kube-system

# （可选）卸载 raven-agent
helm uninstall raven-agent -n kube-system

# 清理 CRDs（谨慎操作）
kubectl delete crd yurtstaticsets.apps.openyurt.io
```

## 故障排除

### 问题：yurt-manager Pod 启动失败

**检查日志：**

```bash
kubectl logs -n kube-system deployment/yurt-manager
```

**常见原因：**
- 集群版本不兼容（需要 K8s 1.20+）
- RBAC 权限不足
- Webhook 证书问题

### 问题：yurt-static-set-yurt-hub ConfigMap 缺少关键参数

**检查 ConfigMap：**

```bash
kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml
```

**修复方法：**

重新安装 yurthub chart 并确保设置了正确的 API Server 地址：

```bash
helm upgrade --install yurthub openyurt/yurthub \
  --namespace kube-system \
  --set kubernetesServerAddr=https://YOUR_API_SERVER:6443 \
  --wait
```

### 问题：边缘节点加入失败

**检查：**

1. 确认集群已设置 `edge-runtime` annotation
2. 确认 ConfigMap 包含正确的配置
3. 检查 API Server 地址是否可从边缘节点访问
4. 查看边缘节点的 kubelet 日志

## 参考资源

- [OpenYurt 官方文档](https://openyurt.io/docs/)
- [OpenYurt Helm Charts](https://github.com/openyurtio/openyurt-helm)
- [Edge Platform OPENYURT-SETUP.md](./OPENYURT-SETUP.md) - 边缘节点配置详解

## 版本兼容性

| OpenYurt 版本 | Kubernetes 版本 | Edge Platform 版本 |
|--------------|----------------|-------------------|
| v1.6.0       | 1.20 - 1.28    | v1.0.0+           |

## 支持

如遇到问题，请：

1. 查看 OpenYurt 组件日志
2. 检查 [OpenYurt Issues](https://github.com/openyurtio/openyurt/issues)
3. 联系 Edge Platform 技术支持
