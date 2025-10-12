# OpenYurt 1.6 安装配置

OpenYurt 1.6 使用 Helm charts 方式安装，提供更现代化的架构和更好的管理能力。

## 目录

- [概述](#概述)
- [前置要求](#前置要求)
- [安装方式](#安装方式)
- [配置说明](#配置说明)
- [验证安装](#验证安装)
- [边缘节点加入](#边缘节点加入)
- [故障排除](#故障排除)
- [卸载](#卸载)

## 概述

本目录包含 OpenYurt 1.6 的 Helm values 配置文件和安装脚本：

```
openyurt-1.6/
├── README.md                    # 本文档
├── install.sh                   # 自动安装脚本
├── yurt-manager-values.yaml     # yurt-manager 配置
├── yurthub-values.yaml          # yurthub 配置（关键配置）
└── raven-agent-values.yaml      # raven-agent 配置（可选）
```

### 核心组件

1. **yurt-manager**: OpenYurt 核心控制器，负责管理边缘节点池、应用等
2. **yurthub**: 边缘节点代理组件，作为节点和云端 API Server 之间的代理
3. **raven-agent**: 边缘网络通信组件（可选），提供跨网络域通信能力

## 前置要求

- Kubernetes 集群 v1.20+
- Helm 3.x
- kubectl 已配置并能访问集群
- 集群 API Server 地址（如 `https://192.168.1.102:6443`）

## 安装方式

### 方式一：使用安装脚本（推荐）

```bash
# 基本安装
./install.sh -a https://192.168.1.102:6443

# 完整安装（包括 raven-agent）
./install.sh -a https://192.168.1.102:6443 -r true

# 使用环境变量
export OPENYURT_API_SERVER=https://192.168.1.102:6443
export INSTALL_RAVEN=true
./install.sh

# 查看帮助
./install.sh -h
```

### 方式二：通过主部署脚本安装

在项目根目录的 `deploy.sh` 中启用 OpenYurt 安装：

```bash
cd ..  # 回到 edge-installer 目录

export KUBECONFIG_PATH=~/.kube/config
export NAMESPACE=edge-system
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://192.168.1.102:6443

./deploy.sh
```

### 方式三：手动安装

```bash
# 1. 添加 OpenYurt Helm 仓库
helm repo add openyurt https://openyurtio.github.io/openyurt-helm
helm repo update

# 2. 安装 yurt-manager
helm upgrade --install yurt-manager openyurt/yurt-manager \
  --namespace kube-system \
  --values yurt-manager-values.yaml \
  --wait \
  --timeout 5m

# 3. 安装 yurthub（必须设置 API Server 地址）
export API_SERVER=https://192.168.1.102:6443
helm upgrade --install yurthub openyurt/yurthub \
  --namespace kube-system \
  --values yurthub-values.yaml \
  --set kubernetesServerAddr=$API_SERVER \
  --wait \
  --timeout 5m

# 4. 可选：安装 raven-agent
helm upgrade --install raven-agent openyurt/raven-agent \
  --namespace kube-system \
  --values raven-agent-values.yaml \
  --wait \
  --timeout 5m
```

## 配置说明

### yurt-manager 配置

主要配置项（`yurt-manager-values.yaml`）：

- **副本数**: 默认 1 个副本
- **资源限制**: CPU 500m, Memory 512Mi
- **节点选择**: 运行在控制平面节点
- **日志级别**: 2（标准日志）

### yurthub 配置（关键配置）

⚠️ **重要**: `yurthub-values.yaml` 包含关键的 `--hub-cert-organizations=system:nodes` 参数。

主要配置项：

```yaml
# API Server 地址（必填）
kubernetesServerAddr: ""  # 需要在安装时指定

# 关键参数（必须保留）
extraArgs:
  - --hub-cert-organizations=system:nodes  # ← CNI 插件必需
  - --v=2
  - --bind-address=127.0.0.1
```

**为什么 `--hub-cert-organizations=system:nodes` 很重要？**

- CNI 插件（如 Calico）需要通过 yurthub 访问 Kubernetes API
- yurthub 使用 TLS 证书与 CNI 插件通信
- 如果证书缺少 `system:nodes` 组织名称，CNI 插件会报 "TLS handshake timeout" 错误
- 导致 Pod 停留在 `ContainerCreating` 状态

### raven-agent 配置（可选）

raven-agent 提供边缘节点间的跨网络域通信能力：

- **VPN 端口**: 4500
- **代理端口**: 10262
- **运行方式**: DaemonSet（自动在所有匹配节点上运行）

如果边缘节点都在同一网络域内，可以不安装此组件。

## 验证安装

### 检查 Pods

```bash
# 检查 OpenYurt Pods
kubectl get pods -n kube-system | grep yurt

# 预期输出：
# yurt-manager-xxx    1/1     Running   0          2m
# yurt-hub-xxx        1/1     Running   0          2m  # 如果有边缘节点
```

### 检查 CRDs

```bash
kubectl get crd | grep openyurt

# 预期输出：
# nodebuckets.apps.openyurt.io
# nodepools.apps.openyurt.io
# yurtstaticsets.apps.openyurt.io
# ...
```

### 检查 YurtStaticSet

```bash
# 查看 YurtStaticSet
kubectl get yurtstaticset -n kube-system

# 查看 yurt-hub 配置
kubectl get yurtstaticset yurt-hub -n kube-system -o yaml
```

### 验证关键配置

```bash
# 验证 ConfigMap 包含 organizations 参数
kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml | \
  grep "hub-cert-organizations"

# 预期输出：
# - --hub-cert-organizations=system:nodes
```

## 边缘节点加入

### 获取加入命令

通过 Edge Platform API 获取节点加入命令：

```bash
# 方式一：通过 API 获取
curl "http://apiserver:8080/oapis/infra.theriseunion.io/v1alpha1/join-token?nodeName=edge-node-01"

# 响应示例：
{
  "spec": {
    "token": "abcdef.0123456789abcdef",
    "command": "echo \"<base64-encoded-script>\" | base64 -d | bash"
  }
}
```

### 在边缘节点执行加入命令

```bash
# 在边缘节点上执行返回的 command
echo "<base64-encoded-script>" | base64 -d | bash
```

### 验证边缘节点

```bash
# 查看节点状态
kubectl get nodes

# 查看边缘节点标签
kubectl get nodes -l node.theriseunion.io/type=edge

# 在边缘节点上检查 yurthub
ssh edge-node "curl -k https://169.254.2.1:10268/v1/healthz"

# 检查边缘节点上的静态 Pod
ssh edge-node "ls -la /etc/kubernetes/manifests/"
```

## 故障排除

### 问题 1: Pod 停留在 ContainerCreating

**症状**:
```
Events:
  Failed to create pod sandbox: rpc error:
  Get "https://169.254.2.1:10268/apis/...": net/http: TLS handshake timeout
```

**原因**: yurthub 配置缺少 `--hub-cert-organizations=system:nodes` 参数

**解决方法**:

```bash
# 1. 检查 ConfigMap
kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml

# 2. 如果缺少 organizations 参数，重新安装 yurthub
helm upgrade --install yurthub openyurt/yurthub \
  --namespace kube-system \
  --values yurthub-values.yaml \
  --set kubernetesServerAddr=https://YOUR_API_SERVER:6443 \
  --wait

# 3. 重启边缘节点上的 yurthub Pod
ssh edge-node "rm -f /etc/kubernetes/manifests/yurt-hub.yaml"
# yurt-hub 会自动重新创建
```

### 问题 2: yurt-manager Pod 启动失败

**检查日志**:
```bash
kubectl logs -n kube-system deployment/yurt-manager
```

**常见原因**:
- 集群版本不兼容（需要 K8s 1.20+）
- RBAC 权限不足
- Webhook 证书问题

### 问题 3: YurtStaticSet 未创建

**检查**:
```bash
# 查看 yurt-manager 日志
kubectl logs -n kube-system deployment/yurt-manager

# 检查 yurt-manager 是否正常运行
kubectl get deployment yurt-manager -n kube-system
```

### 问题 4: 边缘节点 yurthub 无法启动

**在边缘节点上检查**:
```bash
# 查看静态 Pod 清单
cat /etc/kubernetes/manifests/yurt-hub.yaml

# 查看 kubelet 日志
journalctl -xeu kubelet -f

# 检查 yurthub 数据目录
ls -la /var/lib/yurthub/
```

## 卸载

### 使用 Helm 卸载

```bash
# 1. 卸载 Helm releases
helm uninstall yurthub -n kube-system
helm uninstall yurt-manager -n kube-system
helm uninstall raven-agent -n kube-system  # 如果安装了

# 2. 清理 ConfigMaps
kubectl delete configmap yurt-static-set-yurt-hub -n kube-system --ignore-not-found=true

# 3. 清理 YurtStaticSets
kubectl delete yurtstaticset --all -n kube-system --ignore-not-found=true

# 4. 清理 CRDs（谨慎操作，会删除所有相关资源）
kubectl delete crd \
  nodebuckets.apps.openyurt.io \
  nodepools.apps.openyurt.io \
  yurtappsets.apps.openyurt.io \
  yurtstaticsets.apps.openyurt.io
```

### 使用卸载脚本

```bash
# 运行统一卸载脚本
../scripts/uninstall-openyurt-1.6.sh
```

## 参考资源

- [OpenYurt 官方文档](https://openyurt.io/docs/)
- [OpenYurt GitHub](https://github.com/openyurtio/openyurt)
- [OpenYurt Helm Charts](https://github.com/openyurtio/openyurt-helm)
- [上层 OpenYurt 部署文档](../OPENYURT.md)

## 版本兼容性

| OpenYurt 版本 | Kubernetes 版本 | Helm 版本 | Edge Platform 版本 |
|--------------|----------------|-----------|-------------------|
| v1.6.0       | 1.20 - 1.28    | 3.x       | v1.0.0+          |
| v1.6.1       | 1.20 - 1.28    | 3.x       | v1.0.0+          |
| v1.6.2       | 1.20 - 1.29    | 3.x       | v1.0.0+          |

## 最佳实践

1. **配置管理**: 将 values 文件纳入版本控制，便于跟踪变更
2. **参数验证**: 每次安装后验证 `--hub-cert-organizations` 参数是否正确
3. **分步安装**: 先安装 yurt-manager 和 yurthub，验证正常后再安装 raven-agent
4. **监控告警**: 监控 YurtStaticSet 状态和边缘节点 Pod 创建成功率
5. **文档同步**: 保持配置文件和文档同步更新

## 注意事项

⚠️ **重要提醒**:

1. `--hub-cert-organizations=system:nodes` 参数对边缘节点的正常运行至关重要
2. 在任何 OpenYurt 升级或重新部署时必须保留此配置
3. 确保 API Server 地址正确，边缘节点需要能够访问此地址
4. raven-agent 是可选组件，根据实际网络需求决定是否安装
5. 卸载 CRDs 会删除所有相关资源，操作前请备份重要数据

## 联系支持

如有问题，请参考：

1. 上层文档：`../OPENYURT.md`
2. 卸载脚本：`../scripts/uninstall-openyurt-1.6.sh`
3. 主部署脚本：`../deploy.sh`
