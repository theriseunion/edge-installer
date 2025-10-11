# OpenYurt 完整部署指南

## 目录

1. [概述](#概述)
2. [版本选择](#版本选择)
3. [管理端安装](#管理端安装)
4. [边缘节点配置](#边缘节点配置)
5. [Edge Platform 集成](#edge-platform-集成)
6. [故障排除](#故障排除)
7. [卸载说明](#卸载说明)

---

## 概述

OpenYurt 是一个云原生边缘计算框架，通过扩展 Kubernetes 的能力，使其能够无缝地支持边缘场景。

### 支持的版本

- **OpenYurt 1.6.x**: 使用 Helm charts 部署，适合新部署
- **OpenYurt 1.3.x**: 使用 yurtadm 部署，适合兼容性要求高的场景

### 版本对比

| 特性 | OpenYurt 1.3 | OpenYurt 1.6 |
|------|-------------|-------------|
| 安装工具 | yurtadm | Helm charts |
| 节点加入 | yurtadm join | bootstrap token + ConfigMap |
| 控制器 | yurt-controller-manager | yurt-manager |
| 架构 | 单体控制器 | 分离的 Helm 组件 |
| CRD | 较少 | YurtStaticSet 等新 CRD |
| K8s 版本 | 1.16+ | 1.20+ |
| 推荐场景 | 稳定性优先、老版本 K8s | 新部署、现代化架构 |

---

## 版本选择

### OpenYurt 1.6 (推荐用于新部署)

**优势:**
- 更现代的架构设计
- Helm charts 易于管理和升级
- 更好的社区支持和新特性

**前置要求:**
- Kubernetes 集群 v1.20+
- Helm 3.x
- kubectl 已配置并能访问集群

### OpenYurt 1.3 (推荐用于兼容性场景)

**优势:**
- 更稳定、久经考验
- 支持更老版本的 Kubernetes
- 部署更简单

**前置要求:**
- Kubernetes 集群 v1.16+
- 边缘节点已安装 containerd

---

## 管理端安装

### 方式 A: OpenYurt 1.6 (Helm Charts)

#### 1. 使用 deploy.sh 自动安装（推荐）

```bash
# 设置环境变量
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://192.168.1.102:6443  # 替换为你的 API Server 地址

# 运行部署脚本
./deploy.sh
```

完整示例：

```bash
export KUBECONFIG_PATH=~/.kube/192.168.1.102.config
export NAMESPACE=edge-system
export REGISTRY=quanzhenglong.com/edge
export TAG=main
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://192.168.1.102:6443

./deploy.sh
```

#### 2. 手动安装

```bash
# 1. 添加 OpenYurt Helm 仓库
helm repo add openyurt https://openyurtio.github.io/openyurt-helm
helm repo update

# 2. 安装 yurt-manager
helm upgrade --install yurt-manager openyurt/yurt-manager \
  --namespace kube-system \
  --wait \
  --timeout 5m

# 3. 安装 yurthub
export API_SERVER=https://192.168.1.102:6443
helm upgrade --install yurthub openyurt/yurthub \
  --namespace kube-system \
  --set kubernetesServerAddr=$API_SERVER \
  --wait \
  --timeout 5m

# 4. (可选) 安装 raven-agent
helm upgrade --install raven-agent openyurt/raven-agent \
  --namespace kube-system \
  --wait \
  --timeout 5m
```

#### 3. 验证安装

```bash
# 检查 Pods
kubectl get pods -n kube-system | grep yurt

# 检查 CRDs
kubectl get crd | grep openyurt

# 检查 YurtStaticSet
kubectl get yurtstaticset -n kube-system

# 检查 ConfigMap
kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml
```

### 方式 B: OpenYurt 1.3 (yurtadm)

OpenYurt 1.3 的管理端组件可以通过 kubeadm 或标准 Kubernetes 部署方式安装。

```bash
# 从 OpenYurt releases 下载部署 YAML
kubectl apply -f https://raw.githubusercontent.com/openyurtio/openyurt/release-1.3/config/setup/all_in_one.yaml
```

---

## 边缘节点配置

### 关键配置：yurt-hub organizations 参数 ⚠️

**重要**: CNI 插件（如 Calico）需要 yurt-hub 的 TLS 证书包含正确的组织名称。

#### 问题症状

如果缺少此配置，会出现：
- Pod 停留在 `ContainerCreating` 状态
- kubelet 日志显示：`TLS handshake timeout`
- CNI 插件无法通过 yurt-hub 访问 API

#### 解决方案

确保 yurt-hub 配置包含 `--hub-cert-organizations=system:nodes` 参数：

```yaml
# YurtStaticSet 中的正确配置
- command:
  - yurthub
  - --v=2
  - --bind-address=127.0.0.1
  - --server-addr=https://192.168.1.102:6443
  - --node-name=$(NODE_NAME)
  - --bootstrap-file=/var/lib/yurthub/bootstrap-hub.conf
  - --working-mode=edge
  - --namespace=kube-system
  - --hub-cert-organizations=system:nodes  # ← 必须存在
```

#### 验证配置

```bash
# 检查 YurtStaticSet
kubectl get yurtstaticset yurt-hub -n kube-system -o yaml | grep organizations

# 在边缘节点上验证证书
curl -k -v https://169.254.2.1:10268/apis 2>&1 | grep subject
# 应该显示：subject: O=system:nodes; CN=system:node:NODE_NAME
```

### OpenYurt 1.6 边缘节点加入

边缘节点通过 Edge Platform API 自动获取加入命令：

```bash
curl "http://localhost:8080/oapis/infra.theriseunion.io/v1alpha1/join-token?nodeName=edge-node-01"
```

响应示例：

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

### OpenYurt 1.3 边缘节点加入

#### 方式一：从镜像仓库安装（推荐）

```bash
# 1. 设置架构变量
arch=$(uname -m)
if [[ $arch == "aarch64" ]]; then
  arch="arm64"
else
  arch="x86_64"
fi

# 2. 安装 Containerd
/usr/local/bin/oras pull --insecure ${REGISTRY}/edge/containerd_install:${VERSION}-${arch} -o /tmp
/tmp/containerd/install.sh -f /tmp/containerd/cri-containerd-cni-${VERSION}-linux.tar.gz

# 3. 安装 OpenYurt
/usr/local/bin/oras pull --insecure ${REGISTRY}/edge/openyurt_install:1.3.4-${arch} -o /tmp
cd /tmp/openyurt

# 4. 加入集群
./yurtadm join 192.168.1.102:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:xxx... \
  --cri-socket /run/containerd/containerd.sock \
  --node-name edge-node-01 \
  --node-labels node.theriseunion.io/type=edge \
  --hub-cert-organizations=system:nodes
```

#### 方式二：手动下载安装

```bash
# 1. 下载 yurtadm
# x86_64
wget https://github.com/openyurtio/openyurt/releases/download/v1.3.4/yurtadm-linux-amd64
# arm64
wget https://github.com/openyurtio/openyurt/releases/download/v1.3.4/yurtadm-linux-arm64

# 重命名并添加执行权限
mv yurtadm-linux-* yurtadm
chmod +x yurtadm

# 2. 加入集群
./yurtadm join <control-plane-endpoint> \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket /run/containerd/containerd.sock \
  --node-name <node-name> \
  --node-labels node.theriseunion.io/type=edge \
  --hub-cert-organizations=system:nodes
```

#### 生成 Join Token

在控制平面节点上：

```bash
# 创建 bootstrap token
kubeadm token create --print-join-command

# 或者手动创建
kubeadm token create --ttl 24h
kubeadm token list

# 获取 CA 证书哈希
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //'
```

### 验证边缘节点

```bash
# 1. 检查节点状态
kubectl get nodes
kubectl get nodes -l node.theriseunion.io/type=edge

# 2. 在边缘节点上检查组件
ssh edge-node "ps aux | grep yurthub"
ssh edge-node "systemctl status kubelet"
ssh edge-node "ls -la /etc/kubernetes/manifests/"

# 3. 测试 Pod 调度
kubectl run test-pod --image=busybox --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"edge-node-01"}}}' \
  -- sleep 3600
kubectl get pod test-pod -o wide
```

---

## Edge Platform 集成

### 配置集群使用 OpenYurt

#### 通过 Web Console

1. 访问 Edge Platform Console
2. 进入 **集群管理** → 选择集群 → **基本信息**
3. 找到 **边缘运行时** 字段，点击编辑图标
4. 选择 **openyurt** 并保存

#### 通过 kubectl

```bash
# OpenYurt 1.6
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt \
  --overwrite

# OpenYurt 1.3
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt \
  openyurt.io/version=v1.3.4 \
  --overwrite
```

验证配置：

```bash
kubectl get cluster host -o yaml | grep edge-runtime
```

---

## 故障排除

### 问题 1: Pod 停留在 ContainerCreating

**症状:**
```
Events:
  Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox:
  plugin type="calico" failed (add): error getting ClusterInformation:
  Get "https://169.254.2.1:10268/apis/crd.projectcalico.org/v1/clusterinformations/default":
  net/http: TLS handshake timeout
```

**解决方法:**
1. 检查 yurt-hub 配置是否包含 `--hub-cert-organizations=system:nodes`
2. 更新 YurtStaticSet 或 Helm values 添加此参数
3. 重启相关 Pods

### 问题 2: yurt-manager Pod 启动失败

**检查日志:**
```bash
kubectl logs -n kube-system deployment/yurt-manager
```

**常见原因:**
- 集群版本不兼容（需要 K8s 1.20+ for v1.6）
- RBAC 权限不足
- Webhook 证书问题

### 问题 3: ConfigMap 缺少关键参数

**检查:**
```bash
kubectl get configmap yurt-static-set-yurt-hub -n kube-system -o yaml
```

**修复:**
```bash
# OpenYurt 1.6
helm upgrade --install yurthub openyurt/yurthub \
  --namespace kube-system \
  --set kubernetesServerAddr=https://YOUR_API_SERVER:6443 \
  --wait
```

### 问题 4: 节点状态 NotReady

**检查步骤:**
```bash
# 1. 检查 kubelet
ssh edge-node "systemctl status kubelet"
ssh edge-node "journalctl -xeu kubelet -f"

# 2. 检查 yurt-hub
ssh edge-node "netstat -tlnp | grep 10261"
kubectl get pod -n kube-system -o wide | grep yurt-hub

# 3. 检查 CNI
ssh edge-node "ls -la /etc/cni/net.d/"
ssh edge-node "ls -la /opt/cni/bin/"

# 4. 检查 containerd
ssh edge-node "systemctl status containerd"
```

### 问题 5: yurtadm join 失败 (OpenYurt 1.3)

**检查:**
```bash
# 验证 containerd
systemctl status containerd

# 检查网络连通性
ping <control-plane-ip>
telnet <control-plane-ip> 6443

# 查看日志
journalctl -xeu kubelet -f
```

---

## 卸载说明

### 卸载 OpenYurt 1.6

```bash
# 1. 卸载 Helm releases
helm uninstall yurthub -n kube-system
helm uninstall yurt-manager -n kube-system
helm uninstall raven-agent -n kube-system  # 如果安装了

# 2. 清理 ConfigMaps
kubectl delete configmap yurt-static-set-yurt-hub -n kube-system --ignore-not-found=true

# 3. 清理 YurtStaticSets
kubectl delete yurtstaticset --all -n kube-system --ignore-not-found=true

# 4. 清理 CRDs（谨慎操作）
kubectl delete crd \
  gateways.raven.openyurt.io \
  nodebuckets.apps.openyurt.io \
  nodepools.apps.openyurt.io \
  platformadmins.iot.openyurt.io \
  poolservices.network.openyurt.io \
  yurtappdaemons.apps.openyurt.io \
  yurtappoverriders.apps.openyurt.io \
  yurtappsets.apps.openyurt.io \
  yurtstaticsets.apps.openyurt.io
```

使用脚本卸载：
```bash
/Users/neov/src/github.com/edge/apiserver/edge-installer/scripts/uninstall-openyurt-1.6.sh
```

### 卸载边缘节点 (OpenYurt 1.3)

```bash
# 1. 使用 yurtadm 卸载
cd /tmp/openyurt
./yurtadm reset -f

# 2. 清理二进制文件
rm -f /usr/bin/kubeadm /usr/bin/kubelet
rm -f /usr/local/bin/kubeadm /usr/local/bin/kubelet

# 3. 清理配置文件
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/yurthub
```

---

## 版本兼容性

| OpenYurt 版本 | Kubernetes 版本 | Edge Platform 版本 | 部署方式 |
|--------------|----------------|-------------------|---------|
| v1.6.0       | 1.20 - 1.28    | v1.0.0+          | Helm    |
| v1.3.4       | 1.16 - 1.24    | v1.0.0+          | yurtadm |

---

## 参考资源

- [OpenYurt 官方文档](https://openyurt.io/docs/)
- [OpenYurt GitHub](https://github.com/openyurtio/openyurt)
- [OpenYurt Helm Charts](https://github.com/openyurtio/openyurt-helm)
- [yurtadm 使用指南](https://openyurt.io/docs/installation/yurtadm-join)

---

## 最佳实践

1. **自动化部署**: 使用 deploy.sh 脚本部署，确保配置一致性
2. **版本控制**: Helm values 文件纳入版本控制
3. **监控告警**: 监控边缘节点状态和 Pod 创建成功率
4. **配置验证**: 部署后验证 organizations 参数配置正确
5. **文档更新**: 保持运维文档与实际配置同步

**重要提醒**: `--hub-cert-organizations=system:nodes` 配置对边缘节点的正常运行至关重要，在任何 OpenYurt 升级或重新部署时必须保留。
