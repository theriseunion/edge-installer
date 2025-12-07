# Edge Installer Service

Edge Installer 是一个 Kubernetes Operator，用于管理 Edge Platform 组件的安装和生命周期。

## 概述

Edge Installer 提供:

- **声明式安装**: 使用 `Installation` CRD 定义 Edge Platform 安装配置
- **组件管理**: 管理 edge-apiserver, edge-controller, edge-console 和监控栈
- **集群初始化**: 自动初始化集群，创建系统工作空间和命名空间
- **Helm 集成**: 利用 Helm 进行组件部署
- **状态跟踪**: 监控安装进度和组件健康状态

## 架构

Installer 支持三种运行模式:

### 1. Operator 模式 (推荐)

作为 Kubernetes 控制器运行，监听 `Installation` CR 并进行调谐。

```bash
./installer --mode=operator
```

### 2. Install 模式

直接安装指定的 Installation CR。

```bash
./installer --mode=install --installation=edge-platform --namespace=edge-system
```

### 3. Uninstall 模式

卸载指定的 Installation CR。

```bash
./installer --mode=uninstall --installation=edge-platform --namespace=edge-system
```

## 安装阶段

Installer 按以下顺序执行安装阶段:

1. **前提条件检查**: 验证集群是否满足要求
2. **CRD 安装**: 安装所有必需的自定义资源定义
3. **组件安装**: 通过 Helm 部署启用的组件
   - edge-controller (可选初始化)
   - edge-apiserver
   - edge-console
   - 监控栈 (可选)
4. **集群初始化**: 创建主机集群、系统工作空间并分配命名空间
5. **验证**: 验证所有组件是否健康

## 快速开始

### 通过 Kubectl 安装

```bash
# 安装 CRD
make install

# 部署 installer operator
make deploy
```

### 创建 Installation

```yaml
apiVersion: installer.theriseunion.io/v1alpha1
kind: Installation
metadata:
  name: edge-platform
  namespace: edge-system
spec:
  version: "v1.0.0"

  components:
    controller:
      enabled: true
      replicas: 1
      enableInit: true
      image:
        repository: quanzhenglong.com/edge/edge-controller
        tag: latest

    apiserver:
      enabled: true
      replicas: 2
      image:
        repository: quanzhenglong.com/edge/edge-apiserver
        tag: latest

    console:
      enabled: true
      replicas: 1
      image:
        repository: quanzhenglong.com/edge/edge-console
        tag: latest
      ingress:
        enabled: true
        host: console.edge.example.com
        tls: true

    monitoring:
      enabled: true
      prometheus:
        enabled: true
        retention: "15d"
      grafana:
        enabled: true

  initialization:
    enabled: true
    clusterName: "host"
    systemWorkspace: "system-workspace"
    systemNamespaces:
      - "kube-system"
      - "kube-public"
      - "kube-node-lease"
      - "edge-system"
```

应用安装配置:

```bash
kubectl apply -f installation.yaml
```

### 监控安装进度

```bash
# 检查安装状态
kubectl get installation edge-platform -n edge-system

# 查看详细状态
kubectl describe installation edge-platform -n edge-system

# 检查 installer 日志
kubectl logs -f deployment/edge-installer -n edge-system
```

## 开发

### 前提条件

- Go 1.23+
- Kubernetes 1.20+
- kubectl
- make

### 构建

```bash
# 构建 installer 二进制
make build

# 运行测试
make test

# 生成 CRD 和代码
make generate manifests
```

### 本地开发

```bash
# 以 operator 模式本地运行 installer
make run

# 以 install 模式运行
make run-install
```

### 构建 Docker 镜像

```bash
# 构建镜像
make docker-build IMG=quanzhenglong.com/edge/edge-installer:dev

# 推送镜像
make docker-push IMG=quanzhenglong.com/edge/edge-installer:dev
```

## 配置

### 环境变量

- `KUBECONFIG`: kubeconfig 文件路径 (可选，未设置时使用 in-cluster 配置)
- `HELM_DRIVER`: Helm 存储驱动 (默认: "secret")
- `ENABLE_INIT`: 在 controller 启动时启用自动初始化

### 命令行标志

```
  --mode string
        运行模式: operator, install, uninstall (默认 "operator")
  --installation string
        Installation CR 名称 (用于 install/uninstall 模式) (默认 "edge-platform")
  --namespace string
        安装命名空间 (默认 "edge-system")
  --kubeconfig string
        kubeconfig 文件路径
  --master string
        Kubernetes master URL
```

## 故障排除

### 安装失败

检查 Installation 状态:

```bash
kubectl get installation edge-platform -n edge-system -o yaml
```

在 `.status.conditions` 中查找失败条件。

### 组件未就绪

检查组件部署:

```bash
kubectl get pods -n edge-system
kubectl logs deployment/edge-controller -n edge-system
```

### 前提条件检查失败

查看前提条件验证错误:

```bash
kubectl logs deployment/edge-installer -n edge-system | grep -A 10 "Prerequisites"
```

## CRD 参考

完整的 CRD 定义请参考源代码中的 `api/v1alpha1/installation_types.go`。

### Installation 主要字段

- **spec.version**: 要安装的 Edge Platform 版本
- **spec.components**: 组件配置 (controller, apiserver, console, monitoring)
- **spec.initialization**: 集群初始化配置
- **status.phase**: 当前安装阶段
- **status.conditions**: 安装条件列表
- **status.components**: 各组件状态

## 许可证

Copyright 2025 TheriseUnion.

根据 Apache License 2.0 许可。
