# Monitoring Service Helm Chart

Edge 集成监控服务，基于 openFuyao monitoring-service，提供企业级监控能力。

## 概述

该 Helm chart 部署 openFuyao monitoring-service 到 Edge 集群中，并通过 ReverseProxy CRD 实现 API 路径转发。

## 功能特性

- 集成 Prometheus 数据源
- 提供预定义的 PromQL 查询模板
- 支持多种监控指标：节点、Pod、容器、集群等
- 企业级监控 API 兼容性
- 通过 ReverseProxy 实现 API 路径透明转发

## 安装要求

- Kubernetes 1.19+
- Helm 3.2.0+
- Edge apiserver (支持 ReverseProxy CRD)
- Prometheus 服务 (默认在 observability-system namespace)

## 安装

### 1. 基本安装

```bash
# 创建命名空间（如果不存在）
kubectl create namespace observability-system --dry-run=client -o yaml | kubectl apply -f -

# 安装 monitoring-service
helm install monitoring-service ./monitoring-service --namespace observability-system
```

### 2. 自定义配置安装

```bash
helm install monitoring-service ./monitoring-service \
  --namespace observability-system \
  --set image.tag=v1.0.0 \
  --set prometheus.endpoint=custom-prometheus.monitoring.svc \
  --set prometheus.port=9090
```

### 3. 开发环境安装

开发环境和生产环境使用相同的配置，都部署在集群内：

```bash
# 开发和生产使用相同命令
helm install monitoring-service ./monitoring-service \
  --namespace observability-system
```

## 配置参数

### 镜像配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.repository` | 镜像仓库 | `cr.openfuyao.cn/openfuyao/monitoring-service` |
| `image.tag` | 镜像标签 | `latest` |
| `image.pullPolicy` | 镜像拉取策略 | `Always` |

### 服务配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.type` | 服务类型 | `ClusterIP` |
| `service.port` | 服务端口 | `80` |
| `service.targetPort` | 目标端口 | `9083` |
| `service.name` | 服务名称 | `monitoring-service` |

### 资源配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `resources.requests.cpu` | CPU 请求 | `50m` |
| `resources.requests.memory` | 内存请求 | `100Mi` |
| `resources.limits.cpu` | CPU 限制 | `200m` |
| `resources.limits.memory` | 内存限制 | `400Mi` |

### Prometheus 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `prometheus.endpoint` | Prometheus 服务地址 | `edge-prometheus.observability-system.svc` |
| `prometheus.port` | Prometheus 端口 | `9090` |
| `prometheus.scheme` | 连接协议 | `http` |
| `prometheus.insecureSkipVerify` | 跳过 TLS 验证 | `true` |

### ReverseProxy 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `reverseProxy.enabled` | 启用 ReverseProxy | `true` |
| `reverseProxy.name` | ReverseProxy 名称 | `monitoring-service-proxy` |
| `reverseProxy.matcher.path` | 匹配路径 | `/kapis/monitoring.edge.io/v1alpha1/*` |
| `reverseProxy.upstream.host` | 上游主机 | `monitoring-service.edge-system.svc.cluster.local` |
| `reverseProxy.upstream.port` | 上游端口 | `80` |

## API 路径映射

该服务通过 ReverseProxy 实现以下 API 路径转换：

- 输入：`/oapis/monitoring.theriseunion.io/v1alpha1/*`
- 输出：`/rest/monitoring/v1/*`

例如：
- `/oapis/monitoring.theriseunion.io/v1alpha1/clusters/nodes` → `/rest/monitoring/v1/clusters/nodes`
- `/oapis/monitoring.theriseunion.io/v1alpha1/namespaces/metrics` → `/rest/monitoring/v1/namespaces/metrics`

## 验证安装

### 1. 检查 Pod 状态

```bash
kubectl get pods -n observability-system -l app=monitoring-service
```

### 2. 检查服务状态

```bash
kubectl get svc -n observability-system monitoring-service
```

### 3. 检查 ReverseProxy

```bash
kubectl get reverseproxy -n observability-system monitoring-service-proxy
```

### 4. 测试 API

```bash
# 获取 token
export TOKEN=$(curl -s -X POST http://localhost:8080/oauth/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password&client_id=edge-console&client_secret=edge-secret&username=admin&password=P@88w0rd" \
    | jq -r '.access_token')

# 测试监控 API
curl -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8080/oapis/monitoring.theriseunion.io/v1alpha1/clusters/nodes"
```

## 故障排除

### 1. Pod 启动失败

检查日志：
```bash
kubectl logs -n observability-system -l app=monitoring-service
```

常见问题：
- Prometheus 连接失败：检查 `prometheus.endpoint` 配置
- 配置错误：检查 ConfigMap 内容

### 2. API 访问失败

检查 ReverseProxy 状态：
```bash
kubectl describe reverseproxy -n observability-system monitoring-service-proxy
```

确认 apiserver 日志中是否有 ReverseProxy 相关错误。

### 3. 监控数据为空

- 验证 Prometheus 服务可访问性
- 检查 RBAC 权限配置
- 确认监控指标收集正常

## 卸载

```bash
helm uninstall monitoring-service --namespace observability-system
```

## 开发

### 本地开发环境

推荐使用项目根目录的 Makefile 来管理开发环境：

```bash
# 启动完整开发环境（包含可选的本地 monitoring-service）
make dev

# 部署 monitoring-service 到集群
make deploy-monitoring

# 检查服务状态
make dev-status
```

如需本地运行 monitoring-service（可选）：
```bash
# 在 openFuyao monitoring-service 项目中
cd /path/to/openFuyao/monitoring-service
PROMETHEUS_HOST="http://localhost:9090" go run main.go
```

### 更新模板

修改 `values.yaml` 或 `templates/` 目录下的文件后，使用以下命令验证：

```bash
helm template monitoring-service ./monitoring-service --dry-run
```

## 版本历史

- **1.0.0**: 初始版本，集成 openFuyao monitoring-service
  - 支持基本监控指标
  - ReverseProxy API 路径转发
  - Prometheus 数据源集成