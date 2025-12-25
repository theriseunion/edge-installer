# vLLM Metrics Quick Reference

用于前端展示的快速参考，所有指标都已经通过 PrometheusRule 预计算。

## 六大核心监控指标

### 1️⃣ 端到端时延平均值

**指标名称**: `vllm:e2e_request_latency_seconds:avg`

**单位**: 秒 (seconds)

**说明**: 从接收请求到返回完整响应的平均时间

**Grafana 配置**:
```json
{
  "expr": "vllm:e2e_request_latency_seconds:avg",
  "legendFormat": "平均时延 (秒)"
}
```

---

### 2️⃣ 生成第一个词所需时间

**指标名称**: `vllm:time_to_first_token_seconds:avg`

**单位**: 秒 (seconds)

**说明**: 从开始处理到生成第一个 token 的平均时间

**Grafana 配置**:
```json
{
  "expr": "vllm:time_to_first_token_seconds:avg",
  "legendFormat": "首 Token 时间 (秒)"
}
```

---

### 3️⃣ 输入阶段的平均吞吐量

**指标名称**: `vllm:prompt_tokens_throughput:rate`

**单位**: tokens/秒

**说明**: 每秒处理的 prompt tokens 数量

**Grafana 配置**:
```json
{
  "expr": "vllm:prompt_tokens_throughput:rate",
  "legendFormat": "输入吞吐量 (tokens/s)"
}
```

---

### 4️⃣ 输出阶段的平均吞吐量

**指标名称**: `vllm:generation_tokens_throughput:rate`

**单位**: tokens/秒

**说明**: 每秒生成的 tokens 数量

**Grafana 配置**:
```json
{
  "expr": "vllm:generation_tokens_throughput:rate",
  "legendFormat": "输出吞吐量 (tokens/s)"
}
```

---

### 5️⃣ 处理请求的总 Token 数

**指标名称**: `vllm:prompt_tokens_total`

**单位**: tokens (累计值)

**说明**: 累计处理的 prompt tokens 总数

**Grafana 配置**:
```json
{
  "expr": "vllm:prompt_tokens_total",
  "legendFormat": "累计输入 Tokens"
}
```

**或者查看增长率**:
```json
{
  "expr": "vllm:prompt_tokens_total:increase_1h",
  "legendFormat": "过去 1 小时输入 Tokens"
}
```

---

### 6️⃣ 处理响应的总 Token 数

**指标名称**: `vllm:generation_tokens_total`

**单位**: tokens (累计值)

**说明**: 累计生成的 tokens 总数

**Grafana 配置**:
```json
{
  "expr": "vllm:generation_tokens_total",
  "legendFormat": "累计输出 Tokens"
}
```

**或者查看增长率**:
```json
{
  "expr": "vllm:generation_tokens_total:increase_1h",
  "legendFormat": "过去 1 小时输出 Tokens"
}
```

---

## 前端集成示例

### React/TypeScript 示例

```typescript
interface VLLMMetric {
  name: string
  query: string
  unit: string
  description: string
}

export const VLLM_CORE_METRICS: VLLMMetric[] = [
  {
    name: '端到端时延',
    query: 'vllm:e2e_request_latency_seconds:avg',
    unit: '秒',
    description: '请求处理总耗时'
  },
  {
    name: '首 Token 时间',
    query: 'vllm:time_to_first_token_seconds:avg',
    unit: '秒',
    description: '生成第一个词的时间'
  },
  {
    name: '输入吞吐量',
    query: 'vllm:prompt_tokens_throughput:rate',
    unit: 'tokens/s',
    description: '每秒处理的输入 tokens'
  },
  {
    name: '输出吞吐量',
    query: 'vllm:generation_tokens_throughput:rate',
    unit: 'tokens/s',
    description: '每秒生成的 tokens'
  },
  {
    name: '累计输入 Tokens',
    query: 'vllm:prompt_tokens_total',
    unit: 'tokens',
    description: '处理的总输入 tokens'
  },
  {
    name: '累计输出 Tokens',
    query: 'vllm:generation_tokens_total',
    unit: 'tokens',
    description: '生成的总输出 tokens'
  }
]
```

### API 调用示例

```typescript
// 查询 Prometheus API
async function fetchVLLMMetric(query: string): Promise<number> {
  const response = await fetch(
    `http://prometheus-api/api/v1/query?query=${encodeURIComponent(query)}`
  )
  const data = await response.json()
  return parseFloat(data.data.result[0]?.value[1] || '0')
}

// 使用示例
const e2eLatency = await fetchVLLMMetric('vllm:e2e_request_latency_seconds:avg')
console.log(`端到端时延: ${e2eLatency.toFixed(3)} 秒`)
```

---

## 扩展指标（可选）

### 时延分位数

```typescript
export const VLLM_LATENCY_PERCENTILES = [
  { name: 'P50', query: 'vllm:e2e_request_latency_seconds:p50' },
  { name: 'P95', query: 'vllm:e2e_request_latency_seconds:p95' },
  { name: 'P99', query: 'vllm:e2e_request_latency_seconds:p99' }
]
```

### TTFT 分位数

```typescript
export const VLLM_TTFT_PERCENTILES = [
  { name: 'P50', query: 'vllm:time_to_first_token_seconds:p50' },
  { name: 'P95', query: 'vllm:time_to_first_token_seconds:p95' },
  { name: 'P99', query: 'vllm:time_to_first_token_seconds:p99' }
]
```

### 其他有用指标

```typescript
export const VLLM_ADDITIONAL_METRICS = [
  {
    name: '请求速率',
    query: 'vllm:request_rate:rate',
    unit: '请求/秒'
  },
  {
    name: '总吞吐量',
    query: 'vllm:total_tokens_throughput:rate',
    unit: 'tokens/s'
  },
  {
    name: '平均输入长度',
    query: 'vllm:avg_prompt_tokens_per_request',
    unit: 'tokens'
  },
  {
    name: '平均输出长度',
    query: 'vllm:avg_generation_tokens_per_request',
    unit: 'tokens'
  }
]
```

---

## 图表类型建议

### 1. 时延监控 - 折线图

- **X 轴**: 时间
- **Y 轴**: 秒
- **指标**:
  - `vllm:e2e_request_latency_seconds:avg` (主线)
  - `vllm:e2e_request_latency_seconds:p95` (参考线)
  - `vllm:e2e_request_latency_seconds:p99` (参考线)

### 2. TTFT - 折线图

- **X 轴**: 时间
- **Y 轴**: 秒
- **指标**:
  - `vllm:time_to_first_token_seconds:avg` (主线)
  - `vllm:time_to_first_token_seconds:p95` (参考线)

### 3. 吞吐量监控 - 区域堆叠图

- **X 轴**: 时间
- **Y 轴**: tokens/秒
- **指标**:
  - `vllm:prompt_tokens_throughput:rate` (下层)
  - `vllm:generation_tokens_throughput:rate` (上层)

### 4. Token 总量 - 计数器

- **类型**: 单值面板 (Stat Panel)
- **指标**:
  - `vllm:prompt_tokens_total` (左侧)
  - `vllm:generation_tokens_total` (右侧)

### 5. 综合仪表盘 - 多指标仪表盘

```
┌─────────────────────────────────────────────────┐
│ 端到端时延: 1.234s    │ 首 Token: 0.156s     │
├─────────────────────────────────────────────────┤
│ 输入吞吐: 5,432 t/s   │ 输出吞吐: 3,210 t/s  │
├─────────────────────────────────────────────────┤
│ 累计输入: 12.5M       │ 累计输出: 8.3M       │
└─────────────────────────────────────────────────┘
```

---

## 数据刷新建议

- **实时监控**: 5 秒刷新间隔
- **历史分析**: 1 分钟刷新间隔
- **报表统计**: 5 分钟或更长

---

## PromQL 查询技巧

### 查询特定时间范围

```promql
# 过去 1 小时的平均时延
avg_over_time(vllm:e2e_request_latency_seconds:avg[1h])

# 今天的最大时延
max_over_time(vllm:e2e_request_latency_seconds:p99[1d])
```

### 聚合多实例数据

```promql
# 所有实例的平均时延
avg(vllm:e2e_request_latency_seconds:avg)

# 按实例分组
vllm:e2e_request_latency_seconds:avg by (instance)
```

### 计算变化率

```promql
# 时延增长率（与 5 分钟前相比）
(vllm:e2e_request_latency_seconds:avg - vllm:e2e_request_latency_seconds:avg offset 5m)
/
vllm:e2e_request_latency_seconds:avg offset 5m * 100
```

---

## 常见问题

**Q: 为什么有些指标没有数据？**

A: 确保：
1. vLLM 服务正在运行并暴露 metrics 端点
2. Prometheus 正在抓取 vLLM 的 metrics
3. PrometheusRule 已经正确部署到集群
4. 等待 30-60 秒让 recording rules 生效

**Q: 如何验证指标是否正常？**

A: 在 Prometheus UI (http://localhost:9090) 中执行查询：
```promql
vllm:e2e_request_latency_seconds:avg
```

**Q: 累计指标（总 token 数）如何重置？**

A: 累计指标在服务重启后会重置。如果需要持久化统计，建议：
- 定期导出数据到数据库
- 使用 `increase()` 函数计算增量

---

## 联系与支持

如有问题，请查看：
- `vllm-metrics-README.md` - 完整文档
- `vllm-prometheusrule.yaml` - 规则定义
- Prometheus Rules: http://localhost:9090/rules
