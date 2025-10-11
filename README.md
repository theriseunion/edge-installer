# Edge Platform Installer

Edge Platform 的一键安装工具，参考 Kubernetes 的安装模式设计。

## 概述

Edge Installer 提供了一个简单、可靠的方式来部署 Edge Platform 到 Kubernetes 集群。它包含以下组件：

### 核心组件
- **Edge Controller**: Kubernetes operator，管理 Edge 自定义资源
- **Edge API Server**: REST API 服务器，提供多租户 API 端点
- **Edge Console**: Web UI 控制台，提供图形化管理界面

### 可选组件
- **Monitoring Stack**: 包含 Prometheus、Grafana、AlertManager 的完整监控套件
- **Monitoring Service**: 基于 openFuyao 的企业级监控 API 服务，提供丰富的监控指标查询接口
- **OpenYurt**: 云原生边缘计算框架，支持边缘节点管理和边缘应用编排

## 架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Edge        │    │ Edge        │    │ Edge        │
│ Console         │    │ API Server      │    │ Controller      │
│ (Web UI)        │    │ (REST API)      │    │ (Operator)      │
│                 │    │                 │    │                 │
│ Port: 3000      │    │ Port: 8080      │    │ Port: 8080      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        └───────────────────────┼───────────────────────┘
                                │
                    ┌─────────────────┐
                    │ Kubernetes      │
                    │ Cluster         │
                    │                 │
                    └─────────────────┘
```

## 快速开始

### 前提条件

- Kubernetes 集群 (v1.24+)
- kubectl 已配置
- Helm 3.8+
- 足够的集群权限

### 基本安装

```bash
# 克隆仓库
git clone https://github.com/edge/apiserver.git
cd apiserver/edge-installer

# 运行安装脚本
./scripts/install.sh
```

### 指定 kubeconfig 安装

```bash
./scripts/install.sh -k ~/.kube/116.63.161.198.config
```

### 自定义配置安装

```bash
# 自定义命名空间
./scripts/install.sh -n my-edge-system

# 自定义镜像仓库
./scripts/install.sh -r your-registry.com/edge

# 预览安装 (dry-run)
./scripts/install.sh --dry-run
```

### 包含监控组件的安装

```bash
# 使用 deploy.sh 脚本，启用监控组件
ENABLE_MONITORING=true ./deploy.sh

# 或者手动部署监控组件
./deploy.sh  # 先部署核心组件
make deploy-monitoring  # 然后部署监控服务
```

监控组件将部署到 `observability-system` 命名空间，包括：
- Prometheus (监控数据收集)
- Grafana (监控可视化)
- AlertManager (告警管理)
- Monitoring Service (监控 API，包含 ReverseProxy 配置)

### 包含 OpenYurt 的完整安装

如果你需要边缘计算能力，可以同时安装 OpenYurt：

```bash
# 一键安装 Edge Platform + OpenYurt + 监控
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://192.168.1.102:6443
export ENABLE_MONITORING=true

./deploy.sh
```

完整示例（在 192.168.1.102 集群安装所有组件）：

```bash
export KUBECONFIG_PATH=~/.kube/192.168.1.102.config
export NAMESPACE=edge-system
export REGISTRY=quanzhenglong.com/edge
export TAG=main
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://192.168.1.102:6443
export ENABLE_MONITORING=true

./deploy.sh
```

OpenYurt 组件将安装到 `kube-system` 命名空间，包括：
- yurt-manager (OpenYurt 控制器)
- yurthub (边缘节点配置管理)

详细的 OpenYurt 安装和配置请参考 [OPENYURT-INSTALL.md](./OPENYURT-INSTALL.md)

## 镜像配置

默认使用的镜像：

- `quanzhenglong.com/edge/edge-apiserver:main`
- `quanzhenglong.com/edge/edge-controller:main`
- `quanzhenglong.com/edge/edge-console:main`

## 访问 Edge Platform

### 端口转发方式

```bash
# API Server
kubectl port-forward -n edge-system svc/edge-apiserver 8080:8080

# Web Console
kubectl port-forward -n edge-system svc/edge-console 3000:3000
```

访问地址：
- API Server: http://localhost:8080
- Web Console: http://localhost:3000

## 安装后配置

### 配置边缘运行时 (Edge Runtime)

**重要**: 集群安装完成后,需要为集群配置边缘运行时类型,以便支持边缘节点的加入。

#### 通过 Web Console 配置

1. 访问 Web Console (http://localhost:3000 或您配置的 Ingress 地址)
2. 进入 **集群管理** → 选择目标集群 → **基本信息** 页面
3. 找到 **边缘运行时** 字段,点击右侧的编辑图标 ✏️
4. 从下拉菜单中选择合适的运行时:
   - **OpenYurt** - 适用于 OpenYurt 边缘计算框架
   - **KubeEdge** - 适用于 KubeEdge 边缘计算框架
5. 点击 **保存** 按钮完成配置

#### 通过 kubectl 配置

也可以直接通过 kubectl 为集群添加 annotation:

```bash
# 配置 OpenYurt 运行时
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt

# 配置 KubeEdge 运行时
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=kubeedge

# 查看配置结果
kubectl get cluster host -o jsonpath='{.metadata.annotations.cluster\.theriseunion\.io/edge-runtime}'
```

#### 为什么需要配置边缘运行时?

配置边缘运行时后,系统会在生成节点加入命令时自动包含正确的边缘组件安装脚本。如果不配置:
- 无法获取节点加入令牌 (join-token API 会报错)
- 边缘节点无法正确加入集群
- 边缘节点的管理功能将不可用

更多信息请参考 [OpenYurt 安装文档](OPENYURT-SETUP.md)

### Ingress 方式

修改 `edge-console` chart 的 values.yaml：

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    kubernetes.io/ingress.class: nginx
  hosts:
    - host: edge.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
```

## 配置文件

### EdgeConfiguration CRD

通过 `deploy/edge-configuration.yaml` 配置 Edge 平台：

```yaml
apiVersion: installer.edge.theriseunion.io/v1alpha1
kind: EdgeConfiguration
metadata:
  name: edge-installer
  namespace: edge-system
spec:
  edge:
    apiserver:
      enabled: true
      replicas: 1
    controller:
      enabled: true
      replicas: 1
    console:
      enabled: true
      replicas: 1
```

## 脚本选项

### 安装脚本 (install.sh)

```bash
用法: ./scripts/install.sh [OPTIONS]

选项:
    -n, --namespace NAMESPACE       安装命名空间 (默认: edge-system)
    -k, --kubeconfig FILE          kubeconfig 文件路径
    -r, --registry REGISTRY        镜像仓库地址 (默认: quanzhenglong.com/edge)
    --dry-run                      执行 dry-run，不实际安装
    --skip-crd-install             跳过 CRD 安装 (用于升级)
    -t, --timeout TIMEOUT         安装超时时间 (默认: 600s)
    -h, --help                     显示帮助信息
```

### 卸载脚本 (uninstall.sh)

```bash
用法: ./scripts/uninstall.sh [OPTIONS]

选项:
    -n, --namespace NAMESPACE       卸载命名空间 (默认: edge-system)
    -k, --kubeconfig FILE          kubeconfig 文件路径
    --delete-namespace             删除命名空间
    --delete-crd                   删除 CRD 资源
    -h, --help                     显示帮助信息
```

## 监控和日志

### 检查部署状态

```bash
# 查看 Pod 状态
kubectl get pods -n edge-system

# 查看服务状态
kubectl get svc -n edge-system

# 查看日志
kubectl logs -n edge-system deployment/edge-controller
kubectl logs -n edge-system deployment/edge-apiserver
kubectl logs -n edge-system deployment/edge-console
```

### 健康检查

```bash
# API Server 健康检查
curl http://localhost:8080/healthz

# 指标监控
curl http://localhost:8080/metrics
```

## 故障排除

### 常见问题

1. **镜像拉取失败**
   ```bash
   # 检查镜像是否存在
   docker pull quanzhenglong.com/edge/edge-apiserver:main

   # 配置镜像拉取 Secret
   kubectl create secret docker-registry edge-registry \
     --docker-server=quanzhenglong.com \
     --docker-username=your-username \
     --docker-password=your-password \
     -n edge-system
   ```

2. **CRD 冲突**
   ```bash
   # 查看现有 CRD
   kubectl get crd | grep edge

   # 删除冲突的 CRD
   kubectl delete crd edgeconfigurations.installer.edge.theriseunion.io
   ```

3. **权限不足**
   ```bash
   # 检查当前用户权限
   kubectl auth can-i "*" "*" --all-namespaces
   ```

### 日志分析

```bash
# 获取详细日志
kubectl describe pod -n edge-system -l app.kubernetes.io/name=edge-controller
kubectl describe pod -n edge-system -l app.kubernetes.io/name=edge-apiserver
kubectl describe pod -n edge-system -l app.kubernetes.io/name=edge-console
```

## 卸载

### 基本卸载 (保留命名空间和 CRD)

```bash
./scripts/uninstall.sh
```

### 完全卸载

```bash
./scripts/uninstall.sh --delete-namespace --delete-crd
```

## 开发和定制

### 修改 Helm Charts

Edge 使用标准 Helm charts，位于 `../charts/` 目录：

- `../charts/edge-controller/`
- `../charts/edge-apiserver/`
- `../charts/edge-console/`

### 构建自定义镜像

```bash
# 构建 API Server
cd ../edge-apiserver
make docker-build

# 构建 Controller
cd ../edge-apiserver
make docker-build-controller

# 构建 Console
cd ../edge-console
make docker-build
```

## 支持

如有问题，请：

1. 检查日志和事件
2. 查看 GitHub Issues
3. 提交新的 Issue 并附上详细信息

## 许可证

本项目采用与主项目相同的许可证。