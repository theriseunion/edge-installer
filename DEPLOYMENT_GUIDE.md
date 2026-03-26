# Edge Platform 部署指南

基于真实测试环境优化的部署流程。

## 快速开始

### 1. 最简部署（使用默认配置）

```bash
cd edge-installer
./deploy.sh
```

### 2. 使用自定义配置文件部署

```bash
# 1. 复制配置模板
cp custom-values.yaml my-config.yaml

# 2. 编辑配置文件
vim my-config.yaml

# 3. 使用配置文件部署
./deploy.sh --config-file my-config.yaml
```

### 3. 命令行参数部署

```bash
# 基本参数
NAMESPACE=production \
REGISTRY=my-registry.com \
TAG=v1.0.0 \
MODE=host \
./deploy.sh

# 或使用环境变量
export NAMESPACE=production
export REGISTRY=my-registry.com
export TAG=v1.0.0
export MODE=host
./deploy.sh
```

## 部署参数说明

### 必需参数

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `NAMESPACE` | 命名空间 | `edge-system` | `production` |
| `REGISTRY` | 镜像仓库地址 | `quanzhenglong.com` | `my-registry.com` |
| `TAG` | 镜像标签 | `main` | `v1.0.0` |

### 可选参数

| 参数 | 说明 | 默认值 | 可选值 |
|------|------|--------|--------|
| `MODE` | 安装模式 | `all` | `all`, `host`, `member`, `none` |
| `CONFIG_FILE` | 配置文件路径 | 无 | `my-config.yaml` |
| `AUTO_CONFIRM` | 自动确认 | false | `true`, `false` |
| `SKIP_CHARTMUSEUM_UPDATE` | 跳过 ChartMuseum 更新 | false | `true`, `false` |

### 安装模式说明

#### `all` - 完整安装（单集群独立部署）
安装所有组件，包括控制平面和数据平面服务。
- ✅ APIServer
- ✅ Controller
- ✅ Console
- ✅ Monitoring
- ✅ Edge Logs (ClickHouse + OTEL + APIServer + iLogtail)
- ✅ VAST
- ✅ Traefik
- ✅ Bin Downloader

**适用场景**：单集群完整部署、开发测试环境

#### `host` - 主机集群（控制平面）
安装控制平面组件，管理多个成员集群。
- ✅ APIServer
- ✅ Controller
- ✅ Console
- ✅ Monitoring
- ✅ Edge Logs (完整服务)
- ✅ VAST
- ✅ Traefik
- ✅ Bin Downloader

**适用场景**：多集群架构中的主集群

#### `member` - 成员集群
安装成员集群组件，连接到主机集群。
- ✅ APIServer
- ✅ Controller
- ✅ Monitoring (Agent)
- ✅ Edge Logs (仅 iLogtail)
- ❌ Console
- ❌ ClickHouse
- ❌ OTEL Collector

**适用场景**：多集群架构中的成员集群

#### `none` - 仅基础设施
仅安装 Controller 基础设施，不安装任何组件。
- ✅ Controller
- ✅ ChartMuseum
- ❌ 所有业务组件

**适用场景**：手动管理所有组件

## 配置文件说明

### 基础配置

```yaml
# custom-values.yaml

global:
  mode: "all"              # 安装模式
  namespace: "edge-system" # 命名空间
  imageRegistry: "quanzhenglong.com"  # 镜像仓库
```

### 资源配置

#### Controller 配置

```yaml
controller:
  replicaCount: 1
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 50m
      memory: 64Mi
```

#### APIServer 配置

```yaml
autoInstall:
  apiserver:
    enabled: true
    values:
      replicaCount: 1
      resources:
        limits:
          cpu: 1000m
          memory: 1Gi
        requests:
          cpu: 100m
          memory: 128Mi
```

#### ClickHouse 存储配置

```yaml
autoInstall:
  edgeLogs:
    values:
      clickhouse:
        persistence:
          enabled: true
          storageClass: "local"      # StorageClass 名称
          size: 10Gi                 # 存储大小
```

### 服务开关配置

```yaml
autoInstall:
  # 启用/禁用 Console
  console:
    enabled: true

  # 启用/禁用 Monitoring
  monitoring:
    enabled: true

  # 启用/禁用 VAST
  vast:
    enabled: true

  # 启用/禁用 Traefik
  traefik:
    enabled: true
```

## 部署流程说明

### 自动化流程

部署脚本会自动执行以下步骤：

1. **依赖检查** - 检查 kubectl, helm, rsync
2. **集群连接** - 验证 Kubernetes 集群可达性
3. **ChartMuseum 更新** - 打包 charts 并构建镜像
4. **命名空间创建** - 创建必要的命名空间
5. **组件部署** - 使用 Helm 安装 Edge Platform
6. **健康检查** - 等待组件就绪
7. **结果展示** - 显示部署状态和访问方式

### 手动更新 ChartMuseum

如果 ChartMuseum 更新失败，可以手动执行：

```bash
cd edge-installer
make package-charts          # 打包 charts
make docker-build-museum     # 构建 ChartMuseum 镜像
make docker-push-museum      # 推送镜像
kubectl rollout restart deployment/chartmuseum -n edge-system
```

## 故障排查

### 1. ChartMuseum 缺少 Chart

**现象**：Component 安装失败，提示 404 Not Found

**原因**：ChartMuseum 镜像过旧，缺少某些 chart

**解决**：
```bash
cd edge-installer
make update-chartmuseum
```

### 2. ClickHouse StatefulSet 创建失败

**现象**：edge-logs Component 失败，提示 "unable to find api field in struct PodSpec for volumeClaimTemplates"

**原因**：模板结构错误（已在 v1.1 修复）

**解决**：
```bash
# 确保使用最新代码
git pull origin feat/v1.1-yudong
rsync -avrP --delete ~/workspace/theriseunion/edge-installer root@119.8.182.199:/root/
```

### 3. Pod 无法启动（Init 容器卡住）

**现象**：Pod 状态为 `Init:0/1` 或 `Init:0/2`

**原因**：依赖服务未就绪

**排查**：
```bash
# 查看 Init 容器日志
kubectl describe pod <pod-name> -n <namespace>

# 检查依赖服务
kubectl get pods -n logging-system
kubectl get svc -n logging-system
```

### 4. 镜像拉取失败

**现象**：Pod 状态为 `ImagePullBackOff`

**解决**：
```bash
# 检查镜像仓库配置
kubectl get deployment -n edge-system controller -o yaml | grep image:

# 确认镜像存在
docker pull quanzhenglong.com/edge/controller:main
```

## 验证部署

### 检查组件状态

```bash
# 查看 Component 状态
kubectl get component -A

# 查看 Pod 状态
kubectl get pods -n edge-system
kubectl get pods -n logging-system
kubectl get pods -n observability-system

# 查看 PVC 状态（如果启用了持久化）
kubectl get pvc -n logging-system
```

### 检查日志

```bash
# Controller 日志
kubectl logs deployment/controller -n edge-system --tail=100 -f

# APIServer 日志
kubectl logs deployment/apiserver -n edge-system --tail=100 -f

# ClickHouse 日志
kubectl logs statefulset/edge-logs-clickhouse -n logging-system --tail=100 -f
```

### 访问服务

```bash
# Console（使用 NodePort）
kubectl get svc -n edge-system console
# 浏览器访问: http://<node-ip>:30446

# APIServer（端口转发）
kubectl port-forward svc/apiserver 8080:8080 -n edge-system
# API: http://localhost:8080

# 查看 Service
kubectl get svc -n edge-system
```

## 升级部署

### 修改配置后升级

```bash
# 方式 1: 使用配置文件
./deploy.sh --config-file my-config.yaml

# 方式 2: 直接 Helm 升级
helm upgrade edge-platform ./edge-controller \
  --namespace edge-system \
  --set global.imageRegistry=quanzhenglong.com \
  -f my-config.yaml
```

### 滚动更新组件

```bash
# 重启 Controller
kubectl rollout restart deployment/controller -n edge-system

# 重启 APIServer
kubectl rollout restart deployment/apiserver -n edge-system

# 重启 ClickHouse（StatefulSet）
kubectl rollout restart statefulset/edge-logs-clickhouse -n logging-system
```

## 卸载

### 完全卸载

```bash
# 删除 Edge Platform
helm uninstall edge-platform -n edge-system

# 删除命名空间（可选）
kubectl delete namespace edge-system
kubectl delete namespace logging-system
kubectl delete namespace observability-system
kubectl delete namespace rise-vast-system
```

### 保留数据卸载

```bash
# 只删除 Helm release，保留 PVC
helm uninstall edge-platform -n edge-system

# 手动删除 PVC（如需删除数据）
kubectl get pvc -n logging-system
kubectl delete pvc <pvc-name> -n logging-system
```

## 生产环境建议

### 1. 资源规划

| 组件 | 最小配置 | 推荐配置（生产） |
|------|---------|----------------|
| Controller | 100m CPU, 64Mi 内存 | 500m CPU, 512Mi 内存 |
| APIServer | 500m CPU, 512Mi 内存 | 2000m CPU, 2Gi 内存 |
| Console | 500m CPU, 512Mi 内存 | 1000m CPU, 1Gi 内存 |
| ClickHouse | 500m CPU, 1Gi 内存 | 2000m CPU, 4Gi 内存 |
| OTEL Collector | 250m CPU, 256Mi 内存 | 500m CPU, 512Mi 内存 |

### 2. 存储规划

- **ClickHouse**：根据日志量规划，建议至少保留 30 天
  - 小规模（<10GB/天）：50Gi
  - 中规模（10-50GB/天）：200Gi
  - 大规模（>50GB/天）：500Gi+

### 3. 高可用配置

```yaml
autoInstall:
  apiserver:
    values:
      replicaCount: 3  # 3 副本
  edgeLogs:
    values:
      clickhouse:
        # 使用分布式存储
        persistence:
          storageClass: "fast-ssd"
```

### 4. 安全加固

- 修改默认 JWT secret
- 启用 RBAC
- 配置网络策略
- 使用 TLS/HTTPS
- 定期更新镜像

## 常见问题

### Q: 如何修改 Console 的访问地址？

A: 编辑配置文件：
```yaml
autoInstall:
  console:
    values:
      env:
        - name: NEXT_PUBLIC_API_BASE_URL
          value: "http://your-domain:port"
```

### Q: 如何调整 ClickHouse 存储大小？

A: 编辑配置文件：
```yaml
autoInstall:
  edgeLogs:
    values:
      clickhouse:
        persistence:
          size: 100Gi  # 修改大小
```

注意：修改存储大小需要重新创建 PVC，请提前备份重要数据。

### Q: 如何禁用某个组件？

A: 编辑配置文件：
```yaml
autoInstall:
  vast:
    enabled: false  # 禁用 VAST
```

### Q: 成员集群如何配置？

A: 设置 MODE 为 member：
```bash
MODE=member ./deploy.sh
```

或使用配置文件：
```yaml
global:
  mode: "member"
```

## 技术支持

如遇到问题，请提供以下信息：

1. 部署环境信息
2. 配置文件（隐藏敏感信息）
3. 错误日志
4. Pod 和 Component 状态

```bash
# 收集诊断信息
kubectl get component -A > component-status.txt
kubectl get pods -A > pod-status.txt
kubectl logs deployment/controller -n edge-system > controller.log
```
