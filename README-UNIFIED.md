# Edge Platform - 统一安装

## 🚀 快速开始

### 单条命令安装

```bash
# 安装所有组件（独立集群）
make install-all

# 或者直接使用 Helm
helm install edge-platform ./edge-controller
```

### 集群模式

```bash
# Host 集群（包含 Console）
make install-host
# 或
helm install edge-platform ./edge-controller --set global.mode=host

# Member 集群（不包含 Console）
make install-member
# 或
helm install edge-platform ./edge-controller --set global.mode=member

# 仅安装 Controller 基础设施
make install-controller-only
# 或
helm install edge-platform ./edge-controller --set global.mode=none
```

## 📋 组件说明

| 模式 | Controller | APIServer | Console | Monitoring |
|------|------------|------------|---------|------------|
| all | ✅ | ✅ | ✅ | ✅ |
| host | ✅ | ✅ | ✅ | ✅ |
| member | ✅ | ✅ | ❌ | ✅ |
| none | ✅ | ❌ | ❌ | ❌ |

## ⚙️ 自定义配置

### 使用自定义镜像仓库

```bash
helm install edge-platform ./edge-controller \
  --set global.imageRegistry=your-registry.com/edge \
  --set global.imageTag=v1.0.0
```

### 自定义组件配置

```bash
helm install edge-platform ./edge-controller \
  --set autoInstall.apiserver.values.replicaCount=3 \
  --set autoInstall.console.values.service.type=LoadBalancer \
  --set autoInstall.monitoring.enabled=false
```

## 🔧 管理命令

```bash
# 升级
make upgrade-all

# 卸载
make uninstall

# 查看渲染的模板
make template

# 验证 Chart
make lint
```

## 📊 验证安装

```bash
# 检查 Pod 状态
kubectl get pods -n edge-system

# 检查 Component CRs
kubectl get components -A

# 访问 Console（仅 Host 集群）
kubectl port-forward svc/console 3000:3000 -n edge-system
```

## 🆚 新旧安装方式对比

### 旧方式（多步骤）
```bash
# 需要多个步骤
helm install controller ./edge-controller
helm install apiserver ./edge-apiserver
helm install console ./edge-console
# ...
```

### 新方式（单条命令）
```bash
# 一条命令搞定
helm install edge-platform ./edge-controller
```

## 🎯 核心特性

- **单一入口**：一条命令安装所有组件
- **模式化安装**：支持 all/host/member/none 四种模式
- **自动依赖管理**：ChartMuseum 自动管理和分发 Charts
- **声明式管理**：通过 Component CRs 管理组件生命周期
- **向后兼容**：原有的 install.sh 和 Component CR 方式仍然可用