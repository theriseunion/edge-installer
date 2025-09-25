# Edge 监控套件

为 Edge 平台提供完整的可观测性支持，包括 Prometheus、Grafana 和 AlertManager。

## 功能特性

- **Prometheus**: 指标收集和存储
- **Grafana**: 可视化仪表盘和监控面板
- **AlertManager**: 告警管理和通知
- **ServiceMonitor**: 自动服务发现和指标采集

## 快速部署

### 方式一：通过环境变量启用监控

```bash
# 部署 Edge 平台 + 监控套件
ENABLE_MONITORING=true ./deploy.sh
```

### 方式二：单独安装监控套件

```bash
# 先部署 Edge 平台核心组件
./deploy.sh

# 再单独部署监控套件
helm install monitoring ./edge-monitoring --namespace edge-system
```

## 配置选项

主要配置项在 `values.yaml` 中：

```yaml
# 全局配置
global:
  enabled: true              # 是否启用监控套件
  namespace: edge-system     # 部署命名空间

# Prometheus 配置
prometheus:
  enabled: true              # 是否部署 Prometheus
  persistence:
    enabled: true            # 是否启用持久化存储
    size: 20Gi              # 存储大小

# Grafana 配置
grafana:
  enabled: true              # 是否部署 Grafana
  adminPassword: admin123    # 管理员密码

# AlertManager 配置
alertmanager:
  enabled: true              # 是否部署 AlertManager
```

## 访问监控服务

部署完成后，可以通过端口转发访问各个监控服务：

```bash
# 访问 Prometheus (端口 9090)
kubectl port-forward svc/edge-prometheus 9090:9090 -n edge-system

# 访问 Grafana (端口 3000，用户名/密码: admin/admin123)
kubectl port-forward svc/edge-grafana 3000:3000 -n edge-system

# 访问 AlertManager (端口 9093)
kubectl port-forward svc/edge-alertmanager 9093:9093 -n edge-system
```

## 监控指标

### Edge APIServer 指标

- HTTP 请求速率和延迟
- API 调用成功/失败率
- Go 运行时指标 (内存、GC、goroutines)

### Edge Controller 指标

- Controller 调协率
- Controller 错误率
- 工作队列深度

### 系统指标

- Pod 资源使用情况
- 集群节点状态
- 存储使用情况

## 自定义仪表盘

Grafana 预配置了以下仪表盘：

1. **Edge Platform Overview** - 平台整体概况
2. **Edge APIServer Metrics** - API 服务器详细指标
3. **Edge Controller Metrics** - 控制器详细指标

你可以在 Grafana 中导入更多仪表盘或创建自定义面板。

## 告警配置

AlertManager 默认配置包括：

- 高错误率告警
- 资源使用率告警
- 服务可用性告警

可以通过修改 `values.yaml` 中的 `alertmanager.config` 来自定义告警规则和通知方式。

## 故障排除

### 常见问题

1. **Prometheus 无法采集指标**
   - 检查 ServiceMonitor 配置
   - 确认服务端口暴露正确
   - 查看 Prometheus 日志

2. **Grafana 仪表盘无数据**
   - 检查数据源配置
   - 确认 Prometheus 正常工作
   - 验证指标查询语句

3. **存储空间不足**
   - 调整 `prometheus.persistence.size`
   - 配置数据保留策略

### 调试命令

```bash
# 查看所有监控组件状态
kubectl get pods -n edge-system -l component=monitoring

# 查看 Prometheus 配置
kubectl get configmap edge-prometheus-config -n edge-system -o yaml

# 查看服务发现状态
kubectl port-forward svc/edge-prometheus 9090:9090 -n edge-system
# 然后访问 http://localhost:9090/targets
```

## 卸载

```bash
# 卸载监控套件
helm uninstall monitoring -n edge-system

# 清理持久化数据 (可选)
kubectl delete pvc edge-prometheus-pvc edge-grafana-pvc -n edge-system
```