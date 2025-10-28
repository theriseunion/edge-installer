# Edge Platform Installer

Edge Platform 一键部署工具，基于 Kubernetes 和 Helm。

## 概述

Edge Installer 可以快速部署以下组件：

### 核心组件
- **Edge Controller**: Kubernetes operator，管理 Edge 自定义资源
- **Edge API Server**: REST API 服务器，提供多租户 API 端点
- **Edge Console**: Web UI 控制台，提供图形化管理界面

### 可选组件
- **OpenYurt**: 云原生边缘计算框架 (v1.6)
- **Monitoring Stack**: Prometheus + Grafana + AlertManager + Monitoring Service

## 快速开始

### 前提条件

- Kubernetes 集群 (v1.24+)
- kubectl 已配置
- Helm 3.8+

### 基本部署

```bash
# 克隆仓库
git clone https://github.com/edge/apiserver.git
cd apiserver/edge-installer

# 使用默认配置部署
./deploy.sh
```

默认配置：
- 命名空间: `edge-system`
- 镜像仓库: `quanzhenglong.com/edge`
- 镜像标签: `main`

### 配置参数

deploy.sh 使用环境变量配置：

```bash
# 基本配置
export NAMESPACE=edge-system              # 安装命名空间
export KUBECONFIG_PATH=~/.kube/config    # kubeconfig 文件路径
export REGISTRY=quanzhenglong.com/edge   # 镜像仓库地址
export TAG=main                          # 镜像标签
export PULL_POLICY=Always                # 镜像拉取策略

# 功能开关
export ENABLE_MONITORING=false           # 启用监控套件
export INSTALL_OPENYURT=false            # 安装 OpenYurt
```

### 常见部署场景

#### 1. 指定集群部署
```bash
export KUBECONFIG_PATH=~/.kube/prod.config
./deploy.sh
```

#### 2. 启用监控套件
```bash
export ENABLE_MONITORING=true
./deploy.sh
```

#### 3. 完整部署（Edge Platform + OpenYurt + 监控）
```bash
export KUBECONFIG_PATH=~/.kube/your-cluster.config
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=$(kubectl config view --minify | grep server | awk '{print $2}')
export ENABLE_MONITORING=true

./deploy.sh
```

## 脚本说明

### deploy.sh - 主部署脚本

一键部署 Edge Platform，支持 OpenYurt 和监控组件。

**特点:**
- 参数确认机制，避免误操作
- 支持环境变量配置
- 错误处理完善
- 用户交互友好

### update.sh - 更新脚本

用于升级现有部署，支持 CRD 更新和单个组件升级。

```bash
# 更新 API Server（默认）
./update.sh

# 更新指定组件
export COMPONENT=controller  # 可选: apiserver, controller, console
./update.sh

# 自定义配置更新
export TAG=v1.0.0
export NAMESPACE=edge-system
export COMPONENT=console
./update.sh
```

### scripts/uninstall.sh - 卸载脚本

```bash
# 基本卸载（保留命名空间和 CRD）
./scripts/uninstall.sh

# 完全卸载
./scripts/uninstall.sh --delete-namespace --delete-crd
```

## 访问 Edge Platform

### 端口转发

```bash
# API Server
kubectl port-forward -n edge-system svc/apiserver 8080:8080

# Web Console
kubectl port-forward -n edge-system svc/console 3000:3000
```

访问地址：
- API Server: http://localhost:8080
- Web Console: http://localhost:3000

## 配置边缘运行时

**重要**: 部署完成后必须配置边缘运行时，否则无法添加边缘节点。

### 通过 Web Console（推荐）

1. 访问 Console: http://localhost:3000
2. 进入 **集群管理** → 选择集群 → **基本信息**
3. 找到 **边缘运行时** 字段，点击编辑
4. 选择 `OpenYurt` 或 `KubeEdge`
5. 保存配置

### 通过 kubectl

```bash
# 配置 OpenYurt
kubectl annotate cluster host cluster.theriseunion.io/edge-runtime=openyurt

# 配置 KubeEdge
kubectl annotate cluster host cluster.theriseunion.io/edge-runtime=kubeedge
```

## 验证部署

```bash
# 查看 Pod 状态
kubectl get pods -n edge-system

# 查看服务状态
kubectl get svc -n edge-system

# 查看日志
kubectl logs -n edge-system deployment/apiserver
kubectl logs -n edge-system deployment/controller
kubectl logs -n edge-system deployment/console
```

## 故障排除

### 常见问题

1. **资源冲突**
   ```bash
   # 检查现有资源
   kubectl get roletemplates.iam.theriseunion.io

   # 清理冲突资源
   kubectl delete roletemplates.iam.theriseunion.io --all --all-namespaces
   ```

2. **权限不足**
   ```bash
   kubectl auth can-i create namespace
   kubectl auth can-i create deployment
   ```

3. **集群不可达**
   ```bash
   kubectl cluster-info
   ```

4. **镜像不存在**
   ```bash
   docker pull quanzhenglong.com/edge/apiserver:main
   ```

### 监控服务访问

如果启用了监控套件：

```bash
# Prometheus
kubectl port-forward svc/edge-prometheus 9090:9090 -n observability-system

# Grafana (admin/admin123)
kubectl port-forward svc/edge-grafana 3000:3000 -n observability-system

# AlertManager
kubectl port-forward svc/edge-alertmanager 9093:9093 -n observability-system
```

## OpenYurt 支持

### 自动配置 OpenYurt

```bash
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=https://your-api-server:6443
./deploy.sh
```

### 手动设置 API Server 地址

```bash
# 自动获取（推荐）
export OPENYURT_API_SERVER=$(kubectl config view --minify | grep server | awk '{print $2}')

# 手动设置
export OPENYURT_API_SERVER=https://192.168.1.102:6443
```

详细的 OpenYurt 配置请参考 [OPENYURT.md](./OPENYURT.md)

## 最佳实践

1. **开发环境**: 使用 `PULL_POLICY=Always` 确保获取最新镜像
2. **生产环境**: 使用 `PULL_POLICY=IfNotPresent` 避免不必要的镜像拉取
3. **版本管理**: 通过 `TAG` 参数控制部署版本
4. **监控**: 生产环境建议启用 `ENABLE_MONITORING=true`
5. **边缘计算**: 如需边缘节点管理，启用 `INSTALL_OPENYURT=true`

## 支持

如有问题，请：

1. 检查日志和集群状态
2. 查看故障排除章节
3. 提交 GitHub Issue 并附上详细信息

## 许可证

本项目采用与主项目相同的许可证。