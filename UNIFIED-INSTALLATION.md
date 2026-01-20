# Edge Platform - 统一安装文档

## 🎯 设计目标

Edge Installer 已优化为支持**单条 Helm 命令**完成所有组件的安装，大大简化了部署流程。

## 📦 安装架构

```
Helm Install → edge-controller Chart
    ├── 1. 创建所有 CRDs
    ├── 2. 部署 ChartMuseum（含预打包 Charts）
    ├── 3. 部署 Component Controller
    ├── 4. 创建 Component CRs（基于模式）
    └── 5. Controller 自动安装组件
```

## 🚀 快速安装

### 最简单的方式

```bash
# 进入安装目录
cd edge-installer

# 一条命令安装所有组件
helm install edge-platform ./edge-controller
```

### 按集群类型安装

```bash
# Host 集群（管理集群，包含 Console）
helm install edge-platform ./edge-controller --set global.mode=host

# Member 集群（工作集群，不包含 Console）
helm install edge-platform ./edge-controller --set global.mode=member

# 仅安装 Controller 基础设施
helm install edge-platform ./edge-controller --set global.mode=none
```

### 使用 Makefile

```bash
# 所有组件
make install-all

# Host 集群
make install-host

# Member 集群
make install-member
```

## ⚙️ 配置选项

### 1. 全局配置

```yaml
global:
  mode: "all"          # all | host | member | none
  namespace: "edge-system"
  imageRegistry: "quanzhenglong.com/edge"
```

### 2. 组件配置

```yaml
autoInstall:
  apiserver:
    enabled: true
    values:
      replicaCount: 3

  console:
    enabled: true  # 自动根据 global.mode 设置
    values:
      service:
        type: LoadBalancer

  monitoring:
    enabled: true
    values:
      namespace: "observability-system"
```

### 3. ChartMuseum 配置

```yaml
chartmuseum:
  enabled: true
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
```

## 📋 安装模式对比

| 模式 | Controller | APIServer | Console | Monitoring | 使用场景 |
|------|------------|------------|---------|------------|----------|
| **all** | ✅ | ✅ | ✅ | ✅ | 独立集群、开发测试 |
| **host** | ✅ | ✅ | ✅ | ✅ | 管理集群 |
| **member** | ✅ | ✅ | ❌ | ✅ | 工作集群 |
| **none** | ✅ | ❌ | ❌ | ❌ | 仅 Controller |

## 🎛️ 自定义安装示例

### 生产环境

```bash
helm install edge-platform ./edge-controller \
  --set global.mode=host \
  --set global.imageRegistry=your-registry.com/edge \
  --set controller.image.tag=v1.0.0 \
  --set chartmuseum.image.tag=v1.0.0 \
  --set autoInstall.apiserver.values.image.tag=v1.0.0 \
  --set autoInstall.console.values.image.tag=v1.0.0 \
  --set autoInstall.monitoring.values.monitoringService.image.tag=v1.0.0 \
  --set autoInstall.apiserver.values.replicaCount=3 \
  --set autoInstall.apiserver.values.resources.requests.cpu=1000m \
  --set autoInstall.apiserver.values.resources.requests.memory=2Gi
```

### 开发环境

```bash
helm install edge-platform ./edge-controller \
  --set global.mode=member \
  --set global.imageRegistry=local/edge \
  --set controller.image.tag=latest \
  --set chartmuseum.image.tag=latest \
  --set autoInstall.apiserver.values.image.tag=latest \
  --set autoInstall.monitoring.values.monitoringService.image.tag=latest \
  --set autoInstall.monitoring.enabled=false
```

### 禁用特定组件

```bash
helm install edge-platform ./edge-controller \
  --set autoInstall.monitoring.enabled=false \
  --set autoInstall.console.enabled=false
```

## 🔧 管理命令

### 升级

```bash
# 升级到最新版本
helm upgrade edge-platform ./edge-controller

# 升级并指定配置
helm upgrade edge-platform ./edge-controller \
  --set autoInstall.apiserver.values.replicaCount=5
```

### 回滚

```bash
# 查看历史版本
helm history edge-platform

# 回滚到上一个版本
helm rollback edge-platform

# 回滚到指定版本
helm rollback edge-platform 2
```

### 卸载

```bash
# 卸载所有组件
helm uninstall edge-platform
```

## 📊 验证安装

```bash
# 检查所有 Pod
kubectl get pods -n edge-system

# 检查 Component 状态
kubectl get components -A

# 检查 Helm Releases
helm list -n edge-system

# 访问 Console（仅 Host 集群）
kubectl port-forward svc/console 3000:3000 -n edge-system
```

## 🔍 故障排查

### ChartMuseum 问题

```bash
# 检查 ChartMuseum Pod
kubectl get pods -n edge-system -l app.kubernetes.io/component=chartmuseum

# 查看 ChartMuseum 日志
kubectl logs -n edge-system -l app.kubernetes.io/component=chartmuseum

# 测试 ChartMuseum API
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl -s http://edge-controller-chartmuseum.edge-system.svc:8080/api/charts
```

### Component CR 问题

```bash
# 查看 Component 状态
kubectl get components -n edge-system -o wide

# 查看 Component 详情
kubectl describe component edge-apiserver -n edge-system

# 查看 Controller 日志
kubectl logs -n edge-system -l app.kubernetes.io/component=controller
```

## 🆚 与旧版对比

### 旧版部署（多步骤）

```bash
# 需要多个步骤
helm install controller ./edge-controller
helm install apiserver ./edge-apiserver
helm install console ./edge-console
# 或者使用 deploy.sh
./deploy.sh
```

### 新版部署（单步骤）

```bash
# 一条命令搞定
helm install edge-platform ./edge-controller

# 或使用模式
helm install edge-platform ./edge-controller --set global.mode=host
```

## 🔄 迁移指南

### 从 deploy.sh 迁移

```bash
# 旧方式
./deploy.sh

# 新方式（等效）
helm install edge-platform ./edge-controller --set global.mode=all
```

### 从 Component CR 迁移

```bash
# 旧方式
helm install controller ./edge-controller
kubectl apply -f components/host-components.yaml

# 新方式（等效）
helm install edge-platform ./edge-controller --set global.mode=host
```

## 💡 最佳实践

1. **生产环境**：使用 `host` 或 `member` 模式，明确集群角色
2. **开发测试**：使用 `all` 模式，快速部署
3. **镜像仓库**：使用私有仓库管理镜像版本
4. **资源限制**：根据集群规模设置合适的资源限制
5. **监控**：保持监控组件启用，便于问题排查