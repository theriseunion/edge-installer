# vLLM Metrics Recording Rules

这个文件包含了 vLLM 推理服务的 Prometheus recording rules，用于监控 vLLM 服务的性能指标。

## 文件说明

- `vllm-recording-rules.yaml` - 纯 recording rules 配置（可用于非 K8s 环境）
- `vllm-prometheusrule.yaml` - Kubernetes PrometheusRule CRD 资源（用于 K8s 集群）

## 部署到 Kubernetes

```bash
# 应用到集群
kubectl apply -f vllm-prometheusrule.yaml

# 验证部署
kubectl get prometheusrule -n prometheus vllm-recording-rules

# 查看详细信息
kubectl describe prometheusrule -n prometheus vllm-recording-rules
```

## 核心监控指标

### 1. 端到端时延 (E2E Request Latency)

这些指标衡量从接收请求到返回完整响应的总时间。

```promql
# 平均时延
vllm:e2e_request_latency_seconds:avg

# P50 时延（50% 的请求在这个时间内完成）
vllm:e2e_request_latency_seconds:p50

# P95 时延（95% 的请求在这个时间内完成）
vllm:e2e_request_latency_seconds:p95

# P99 时延（99% 的请求在这个时间内完成）
vllm:e2e_request_latency_seconds:p99
```

**使用场景**: 监控整体服务性能，设置 SLA 告警阈值。

---

### 2. 生成第一个词所需时间 (Time to First Token - TTFT)

衡量从开始处理到生成第一个 token 的时间，反映模型的响应速度。

```promql
# 平均 TTFT
vllm:time_to_first_token_seconds:avg

# P50 TTFT
vllm:time_to_first_token_seconds:p50

# P95 TTFT
vllm:time_to_first_token_seconds:p95

# P99 TTFT
vllm:time_to_first_token_seconds:p99
```

**使用场景**: 优化用户体验，降低首次响应延迟。

---

### 3. 输入阶段吞吐量 (Prompt Tokens Throughput)

每秒处理的 prompt tokens 数量。

```promql
# tokens/秒
vllm:prompt_tokens_throughput:rate
```

**使用场景**: 监控输入处理能力，评估模型的并发处理能力。

---

### 4. 输出阶段吞吐量 (Generation Tokens Throughput)

每秒生成的 tokens 数量。

```promql
# tokens/秒
vllm:generation_tokens_throughput:rate
```

**使用场景**: 监控生成速度，评估模型的输出效率。

---

### 5. 处理请求的总 Token 数 (Total Prompt Tokens)

累计处理的 prompt tokens 总数。

```promql
# 累计总数（使用原始指标）
vllm:prompt_tokens_total

# 过去 1 小时增长量
vllm:prompt_tokens_total:increase_1h
```

**使用场景**: 计费统计，容量规划。

---

### 6. 处理响应的总 Token 数 (Total Generation Tokens)

累计生成的 tokens 总数。

```promql
# 累计总数（使用原始指标）
vllm:generation_tokens_total

# 过去 1 小时增长量
vllm:generation_tokens_total:increase_1h
```

**使用场景**: 计费统计，容量规划。

---

## 额外有用的指标

### 请求速率 (Requests per Second)

```promql
vllm:request_rate:rate
```

监控每秒处理的请求数量。

---

### 总吞吐量 (Total Tokens Throughput)

```promql
vllm:total_tokens_throughput:rate
```

输入 + 输出的总 tokens/秒。

---

### 平均每请求的 Prompt Tokens 数

```promql
vllm:avg_prompt_tokens_per_request
```

帮助分析请求的复杂度。

---

### 平均每请求的 Generation Tokens 数

```promql
vllm:avg_generation_tokens_per_request
```

帮助分析响应的长度特征。

---

## 在 Grafana 中使用

### 创建时延监控面板

```json
{
  "title": "vLLM E2E Latency",
  "targets": [
    {
      "expr": "vllm:e2e_request_latency_seconds:avg",
      "legendFormat": "平均时延"
    },
    {
      "expr": "vllm:e2e_request_latency_seconds:p95",
      "legendFormat": "P95 时延"
    },
    {
      "expr": "vllm:e2e_request_latency_seconds:p99",
      "legendFormat": "P99 时延"
    }
  ]
}
```

### 创建吞吐量监控面板

```json
{
  "title": "vLLM Throughput",
  "targets": [
    {
      "expr": "vllm:prompt_tokens_throughput:rate",
      "legendFormat": "Prompt Tokens/s"
    },
    {
      "expr": "vllm:generation_tokens_throughput:rate",
      "legendFormat": "Generation Tokens/s"
    },
    {
      "expr": "vllm:total_tokens_throughput:rate",
      "legendFormat": "Total Tokens/s"
    }
  ]
}
```

---

## 告警规则建议

### 高时延告警

```yaml
- alert: VLLMHighLatency
  expr: vllm:e2e_request_latency_seconds:p95 > 5
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "vLLM P95 时延过高"
    description: "P95 时延已超过 5 秒，当前值: {{ $value }}s"
```

### 低吞吐量告警

```yaml
- alert: VLLMLowThroughput
  expr: vllm:total_tokens_throughput:rate < 100
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "vLLM 吞吐量过低"
    description: "总吞吐量低于 100 tokens/s，当前值: {{ $value }} tokens/s"
```

---

## 性能优化指南

### 根据指标优化

1. **TTFT 过高**:
   - 检查 prompt 长度
   - 优化模型加载
   - 增加 GPU 资源

2. **生成吞吐量低**:
   - 调整 batch size
   - 优化 KV cache
   - 检查 GPU 利用率

3. **端到端时延不稳定**:
   - 检查 P95/P99 与平均值的差距
   - 分析请求队列
   - 优化调度策略

---

## 维护说明

### 更新 Recording Rules

1. 修改 `vllm-prometheusrule.yaml`
2. 重新应用到集群:
   ```bash
   kubectl apply -f vllm-prometheusrule.yaml
   ```
3. Prometheus 会自动重新加载规则（通常在 30 秒内）

### 验证 Recording Rules

```bash
# 查看 Prometheus 目标
kubectl port-forward -n prometheus svc/prometheus-operated 9090:9090

# 访问 http://localhost:9090/rules
# 或使用 API 查询
curl 'http://localhost:9090/api/v1/rules' | jq '.data.groups[] | select(.name == "vllm-service-monitoring-rules")'
```

---

## 相关资源

- [vLLM Metrics Documentation](https://docs.vllm.ai/en/latest/serving/metrics.html)
- [Prometheus Recording Rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
- [Kubernetes Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)

---

## 版本历史

- **v1.0.0** (2025-12-18): 初始版本，包含 6 个核心指标和 4 个扩展指标
