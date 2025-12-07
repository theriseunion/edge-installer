# Edge Platform 安装指南

## 概述

Edge Platform 提供两种安装方式:

1. **Component CR 驱动安装** (`deploy-component.sh`) - **推荐方式**
   - 声明式管理,符合 Kubernetes 最佳实践
   - 使用 Component CR 驱动自动化安装
   - 支持组件生命周期管理(安装/升级/卸载)
   - 完整的状态追踪和错误反馈

2. **传统 Helm 安装** (`deploy.sh`) - **遗留方式**
   - 直接使用 Helm 命令安装
   - 快速简单,适合测试环境
   - 缺少自动化管理能力

## 安装方式选择

### 使用 Component CR 安装(推荐)

**适用场景:**
- 生产环境部署
- 需要完整的组件生命周期管理
- 多集群环境
- 需要统一的声明式配置

**优势:**
- ✅ 声明式管理: 通过 Component CR 描述期望状态
- ✅ 自动化: Component Controller 自动执行 Helm 操作
- ✅ 幂等性: 重复 apply 安全可靠
- ✅ 状态追踪: 通过 Component status 了解安装状态
- ✅ 变更检测: 自动检测配置变化并升级
- ✅ 统一管理: 所有组件使用相同的管理模式

**使用方法:**
```bash
cd edge-installer
./deploy-component.sh
```

**安装流程:**
```
1. 安装 Controller (包含所有 CRDs)
   └─> Helm install edge-controller
       ├─> CRDs 自动安装 (来自 crds/ 目录)
       └─> Controller Pod 启动

2. 创建 Component CRs
   ├─> edge-apiserver Component
   ├─> edge-console Component
   └─> edge-monitoring Component (可选)

3. Component Controller 自动安装组件
   ├─> Watch Component CRs
   ├─> 执行 Helm install/upgrade
   └─> 更新 Component status

4. 验证安装结果
   ├─> 检查 Pod 状态
   ├─> 检查 Component CRs
   └─> 检查 Helm Releases
```

### 使用传统 Helm 安装

**适用场景:**
- 开发测试环境
- 快速验证功能
- 临时部署

**优势:**
- ✅ 简单直接
- ✅ 无需理解 Component CR 概念
- ✅ 安装速度快

**劣势:**
- ❌ 缺少自动化管理
- ❌ 配置变更需要手动操作
- ❌ 无状态追踪

**使用方法:**
```bash
cd edge-installer
./deploy.sh
```

## 环境要求

- Kubernetes 集群 v1.29+
- kubectl 访问权限
- Helm 3.x 客户端

## Component CR 安装详细说明

### 步骤 1: 安装 Controller

Controller Helm Chart 包含:
- 所有 CRD 定义 (17 个,位于 `edge-controller/crds/`)
- Controller Deployment
- 必要的 RBAC 配置

```bash
helm upgrade --install controller ./edge-controller \
  --namespace edge-system \
  --set image.repository=quanzhenglong.com/edge/controller \
  --set image.tag=main \
  --wait
```

**验证 CRDs 安装:**
```bash
kubectl get crd | grep theriseunion.io
```

**验证 Controller 运行:**
```bash
kubectl get pods -n edge-system
kubectl logs -n edge-system deployment/controller
```

### 步骤 2: 创建 Component CRs

使用提供的模板创建 Component CRs:

**Host 集群 (包含 Console):**
```bash
kubectl apply -f components/host-components.yaml
```

**Member 集群 (不含 Console):**
```bash
kubectl apply -f components/member-components.yaml
```

**或手动创建单个组件:**
```yaml
apiVersion: ext.theriseunion.io/v1alpha1
kind: Component
metadata:
  name: edge-apiserver
  namespace: edge-system
spec:
  type: apiserver
  enabled: true
  chart:
    name: edge-apiserver
    namespace: edge-system
    releaseName: edge-apiserver
  values:
    image:
      repository: quanzhenglong.com/edge/apiserver
      tag: main
      pullPolicy: Always
```

### 步骤 3: 等待 Component Controller 安装

Component Controller 会:
1. Watch Component CR 创建事件
2. 计算 Spec Hash (用于变更检测)
3. 调用 Helm SDK 执行安装
4. 更新 Component Status

**监控安装进度:**
```bash
# 查看 Component 状态
kubectl get components -n edge-system
kubectl get component edge-apiserver -n edge-system -o yaml

# 查看 Controller 日志
kubectl logs -n edge-system deployment/controller -f

# 查看 Helm Releases
helm list -n edge-system
```

**Component Status 字段说明:**
- `phase`: Pending → Installing → Installed → Failed
- `releaseName`: Helm Release 名称
- `releaseVersion`: Helm Release 版本号
- `observedHash`: Spec Hash (用于变更检测)
- `message`: 详细状态信息

### 步骤 4: 验证安装

```bash
# 查看 Pod 状态
kubectl get pods -n edge-system

# 查看 Component CRs
kubectl get components -n edge-system

# 查看 Helm Releases
helm list -n edge-system

# 访问服务
kubectl port-forward -n edge-system svc/edge-console 3000:3000
kubectl port-forward -n edge-system svc/edge-apiserver 8080:8080
```

## 组件管理操作

### 更新组件配置

修改 Component CR 的 `spec.values`:

```bash
kubectl edit component edge-apiserver -n edge-system
```

修改后,Component Controller 会:
1. 检测到 Spec 变化 (Hash 不同)
2. 自动执行 Helm Upgrade
3. 更新 Status

### 禁用组件

```bash
kubectl patch component edge-apiserver -n edge-system \
  --type=merge -p '{"spec":{"enabled":false}}'
```

### 启用组件

```bash
kubectl patch component edge-apiserver -n edge-system \
  --type=merge -p '{"spec":{"enabled":true}}'
```

### 卸载组件

删除 Component CR:
```bash
kubectl delete component edge-apiserver -n edge-system
```

Component Controller 会:
1. 执行 Helm Uninstall
2. 清理相关资源
3. 删除 Component CR

### 强制重新安装

删除 `status.observedHash` 触发重新安装:
```bash
kubectl patch component edge-apiserver -n edge-system \
  --type=json -p='[{"op":"remove","path":"/status/observedHash"}]'
```

## 故障排查

### Component 安装失败

**症状:** `status.phase` 为 `Failed`

**排查步骤:**
```bash
# 1. 查看 Component Status Message
kubectl get component edge-apiserver -n edge-system -o jsonpath='{.status.message}'

# 2. 查看 Controller 日志
kubectl logs -n edge-system deployment/controller | grep apiserver

# 3. 查看 Helm Release 状态
helm status edge-apiserver -n edge-system

# 4. 查看 Pod 事件
kubectl describe pod <pod-name> -n edge-system
```

**常见问题:**
- **镜像拉取失败**: 检查镜像仓库地址和凭证
- **Chart 不存在**: 确认 CHARTS_PATH 环境变量正确
- **配置错误**: 检查 `spec.values` 是否符合 Chart 要求
- **资源不足**: 检查节点资源配额

### Controller 无响应

**症状:** Component CR 创建后无变化

**排查步骤:**
```bash
# 1. 检查 Controller 是否运行
kubectl get pods -n edge-system | grep controller

# 2. 查看 Controller 日志
kubectl logs -n edge-system deployment/controller

# 3. 检查 CRD 是否安装
kubectl get crd components.ext.theriseunion.io

# 4. 检查 RBAC 权限
kubectl auth can-i create components --as=system:serviceaccount:edge-system:controller
```

### CRD 未安装

**症状:** 创建 Component CR 失败

**解决方案:**
```bash
# 手动应用 CRD
kubectl apply -f edge-controller/crds/ext.theriseunion.io_components.yaml

# 或重新安装 Controller
helm upgrade --install controller ./edge-controller \
  --namespace edge-system \
  --wait
```

## 环境变量配置

### deploy-component.sh 支持的环境变量

| 变量名               | 默认值                      | 说明                          |
|---------------------|----------------------------|-------------------------------|
| NAMESPACE           | edge-system                | 安装命名空间                   |
| KUBECONFIG          | ~/.kube/config             | Kubernetes 配置文件路径        |
| REGISTRY            | quanzhenglong.com/edge     | 镜像仓库地址                   |
| TAG                 | main                       | 镜像标签                       |
| PULL_POLICY         | Always                     | 镜像拉取策略                   |
| ENABLE_MONITORING   | false                      | 是否安装监控套件               |
| CHARTS_PATH         | $(pwd)                     | Helm Charts 路径              |

**使用示例:**
```bash
NAMESPACE=test-system \
TAG=v1.0.0 \
ENABLE_MONITORING=true \
./deploy-component.sh
```

## 架构说明

### Component CR 驱动流程

```
用户
  │
  └─> kubectl apply -f component.yaml
           │
           v
      Component CR (ext.theriseunion.io/v1alpha1)
           │
           │ (watch)
           v
      Component Controller
           │
           ├─> 计算 Spec Hash
           ├─> 检测变化
           └─> 调用 Helm SDK
                 │
                 ├─> Install (新建)
                 ├─> Upgrade (变更)
                 └─> Uninstall (删除)
                       │
                       v
                  Helm Release
                       │
                       v
                  Kubernetes Resources (Pods, Services, etc.)
```

### 变更检测机制

Component Controller 使用 Spec Hash 检测配置变化:

```go
currentHash := calculateHash(component.Spec)

if component.Status.ObservedHash == currentHash {
    // 无变化,跳过
    return reconcile.Result{}, nil
}

// 有变化,执行升级
helmClient.Upgrade(...)

// 更新 Hash
component.Status.ObservedHash = currentHash
```

这保证了:
- ✅ 只在真正变化时才执行 Helm 操作
- ✅ 避免不必要的资源消耗
- ✅ 支持配置漂移自动修复

## 迁移指南

### 从 deploy.sh 迁移到 deploy-component.sh

**步骤 1: 备份现有环境**
```bash
# 导出 Helm Releases
helm list -n edge-system -o yaml > releases-backup.yaml

# 导出资源配置
kubectl get all -n edge-system -o yaml > resources-backup.yaml
```

**步骤 2: 卸载旧环境**
```bash
helm uninstall apiserver -n edge-system
helm uninstall controller -n edge-system
helm uninstall console -n edge-system
```

**步骤 3: 使用新方式安装**
```bash
./deploy-component.sh
```

**步骤 4: 验证迁移**
```bash
# 检查 Component CRs
kubectl get components -n edge-system

# 检查 Helm Releases
helm list -n edge-system

# 验证功能
kubectl get pods -n edge-system
```

## 卸载

### Component CR 方式卸载

```bash
# 删除所有 Component CRs
kubectl delete components --all -n edge-system

# 等待 Component Controller 清理完成
# 然后卸载 Controller
helm uninstall controller -n edge-system

# 删除命名空间
kubectl delete namespace edge-system
```

### 传统 Helm 方式卸载

```bash
helm uninstall apiserver -n edge-system
helm uninstall controller -n edge-system
helm uninstall console -n edge-system
kubectl delete namespace edge-system
```

## 参考文档

- [Component 安装流程设计文档](../edge-apiserver/docs-installer/component-installation-flow.md)
- [Component CRD 定义](./edge-controller/crds/ext.theriseunion.io_components.yaml)
- [Component Controller 实现](../edge-apiserver/internal/controller/ext/component_controller.go)
- [Helm Client 实现](../edge-apiserver/pkg/helm/client.go)

## 后续计划

1. **Host 集群支持 Component CR 安装** (下一版本)
   - 移除 deploy.sh 对 Host 集群的依赖
   - Host 集群也使用 Component CR 管理

2. **Console 多集群支持** (未来版本)
   - Member 集群也可以安装 Console
   - 支持本地化 UI 访问

3. **Proxy 连接模式** (未来版本)
   - Member 集群通过 Agent 主动连接 Host
   - 支持穿透防火墙/NAT 场景

## 许可证

Apache License 2.0
