# OpenYurt 1.3 安装指南

## 概述

本文档说明如何安装 OpenYurt 1.3.4 到边缘节点。OpenYurt 1.3 使用 `yurtadm` 工具进行节点加入,类似于 Kubernetes 的 `kubeadm`。

## 前置要求

### 边缘节点要求
- 操作系统: Linux (Ubuntu/CentOS/RHEL)
- 架构: x86_64 或 arm64
- Containerd 已安装并运行
- 网络可访问控制平面

### 控制平面要求
- Kubernetes 集群 v1.20+
- OpenYurt 控制平面组件已部署

## 安装方式

### 方式一:从 edge-ota 镜像仓库安装(推荐)

此方式使用 oras 工具从镜像仓库拉取预打包的 OpenYurt 1.3.4 安装包。

#### 1. 安装 Containerd

```bash
# 设置架构变量
arch=$(uname -m)
if [[ $arch == "aarch64" ]]; then
  arch="arm64"
else
  arch="x86_64"
fi

# 从镜像仓库拉取 containerd 安装包
/usr/local/bin/oras pull --insecure ${fileServerRegistry}/edge/containerd_install:${version}-${arch} -o /tmp

# 执行安装脚本
/tmp/containerd/install.sh -f /tmp/containerd/cri-containerd-cni-${version}-linux.tar.gz
```

#### 2. 安装 OpenYurt 1.3.4

```bash
# 设置架构变量
arch=$(uname -m)
if [[ $arch == "aarch64" ]]; then
  arch="arm64"
else
  arch="x86_64"
fi

# 从镜像仓库拉取 OpenYurt 安装包
/usr/local/bin/oras pull --insecure ${fileServerRegistry}/edge/openyurt_install:1.3.4-${arch} -o /tmp

# 进入安装目录
cd /tmp/openyurt

# 执行加入命令(需要从控制平面获取)
${join_command}
```

**示例加入命令:**
```bash
./yurtadm join 192.168.1.102:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:xxx... \
  --cri-socket /run/containerd/containerd.sock \
  --node-name edge-node-01 \
  --node-labels node.theriseunion.io/type=edge
```

### 方式二:手动下载安装

#### 1. 下载 yurtadm

从 OpenYurt GitHub releases 下载对应版本:

```bash
# x86_64
wget https://github.com/openyurtio/openyurt/releases/download/v1.3.4/yurtadm-linux-amd64

# arm64
wget https://github.com/openyurtio/openyurt/releases/download/v1.3.4/yurtadm-linux-arm64

# 重命名并添加执行权限
mv yurtadm-linux-* yurtadm
chmod +x yurtadm
```

#### 2. 加入集群

```bash
./yurtadm join <control-plane-endpoint> \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket /run/containerd/containerd.sock \
  --node-name <node-name> \
  --node-labels node.theriseunion.io/type=edge
```

## 生成加入令牌

### 在控制平面节点上

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

## 验证安装

### 1. 检查节点状态

在控制平面上:
```bash
kubectl get nodes
kubectl get nodes -l node.theriseunion.io/type=edge
```

### 2. 检查边缘节点组件

在边缘节点上:
```bash
# 检查 yurthub 进程
ps aux | grep yurthub

# 检查 kubelet
systemctl status kubelet

# 检查 yurthub 静态 pod
ls -la /etc/kubernetes/manifests/
```

### 3. 检查配置文件

```bash
# kubelet 配置
cat /etc/kubernetes/kubelet.conf

# yurthub 配置
cat /var/lib/yurthub/bootstrap-hub.conf
```

## 卸载 OpenYurt

### 在边缘节点上

```bash
# 使用 yurtadm 卸载
cd /tmp/openyurt
./yurtadm reset -f

# 清理二进制文件
rm -f /usr/bin/kubeadm /usr/bin/kubelet
rm -f /usr/local/bin/kubeadm /usr/local/bin/kubelet

# 清理配置文件
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/yurthub
```

## 故障排除

### 问题 1: yurtadm join 失败

**检查:**
```bash
# 验证 containerd 运行状态
systemctl status containerd

# 检查网络连通性
ping <control-plane-ip>
telnet <control-plane-ip> 6443

# 查看 yurtadm 日志
journalctl -xeu kubelet
```

### 问题 2: yurthub 无法启动

**检查:**
```bash
# 查看 static pod manifest
cat /etc/kubernetes/manifests/yurthub.yaml

# 查看 kubelet 日志
journalctl -xeu kubelet -f

# 检查证书
ls -la /var/lib/yurthub/
```

### 问题 3: 节点显示 NotReady

**可能原因:**
1. CNI 插件未安装或配置错误
2. yurthub 与 API server 连接问题
3. containerd 配置问题

**解决方法:**
```bash
# 检查 CNI 配置
ls -la /etc/cni/net.d/
ls -la /opt/cni/bin/

# 检查 containerd 配置
cat /etc/containerd/config.toml

# 重启 kubelet
systemctl restart kubelet
```

## OpenYurt 1.3 vs 1.6 对比

| 特性 | OpenYurt 1.3 | OpenYurt 1.6 |
|------|-------------|-------------|
| 安装工具 | yurtadm | Helm charts (yurt-manager + yurthub) |
| 节点加入 | yurtadm join | bootstrap token + ConfigMap |
| 控制器 | yurt-controller-manager | yurt-manager |
| 架构 | 单体控制器 | 分离的 Helm 组件 |
| CRD | 较少 | YurtStaticSet 等新 CRD |
| 版本要求 | K8s 1.16+ | K8s 1.20+ |

## 与 Edge Platform 集成

### 配置集群使用 OpenYurt 1.3

```bash
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt \
  openyurt.io/version=v1.3.4 \
  --overwrite
```

### 生成边缘节点加入命令

通过 Edge Platform API:
```bash
curl "http://localhost:8080/oapis/infra.theriseunion.io/v1alpha1/join-token?nodeName=edge-node-01"
```

## 参考资源

- [OpenYurt 官方文档](https://openyurt.io/docs/)
- [OpenYurt GitHub](https://github.com/openyurtio/openyurt)
- [yurtadm 使用指南](https://openyurt.io/docs/installation/yurtadm-join)

## 版本兼容性

| OpenYurt 版本 | Kubernetes 版本 | Edge Platform 版本 |
|--------------|----------------|-------------------|
| v1.3.4       | 1.16 - 1.24    | v1.0.0+          |

## 迁移建议

如果您当前运行 OpenYurt 1.6,建议:

1. **评估需求**: 1.6 提供更现代的架构,但 1.3 更稳定
2. **测试环境验证**: 先在测试集群验证 1.3 的兼容性
3. **逐步迁移**: 不要在生产环境直接降级

**注意**: OpenYurt 1.3 到 1.6 不是简单的升级路径,涉及架构变更。
