# OpenYurt Configuration Helm Chart

此 Helm Chart 用于配置 Edge Platform 的 OpenYurt 边缘运行时。

## 功能

- 创建 OpenYurt 所需的 ConfigMap (`yurt-static-set-yurt-hub`)
- 配置边缘节点加入所需的 API Server 地址
- 提供 Cluster CR 注解配置助手
- 支持自定义 YurtHub 配置

## 前置条件

- Kubernetes 集群已安装 (v1.24+)
- kubectl 已配置并能访问集群
- Helm 3.8+
- Edge Platform 核心组件已部署

## 快速开始

### 1. 配置 values.yaml

编辑 `values.yaml` 文件，**必须设置** API Server 地址：

```yaml
openyurt:
  apiServer:
    # 替换为您的实际 API Server 地址
    endpoint: "https://192.168.1.102:6443"
```

### 2. 安装 Chart

```bash
# 使用 values.yaml 中的配置
helm install openyurt-config . --namespace kube-system

# 或者通过命令行参数指定 API Server
helm install openyurt-config . --namespace kube-system \
  --set openyurt.apiServer.endpoint=https://192.168.1.102:6443
```

### 3. 验证安装

```bash
# 检查 ConfigMap 是否创建
kubectl get configmap yurt-static-set-yurt-hub -n kube-system

# 查看 ConfigMap 内容
kubectl describe configmap yurt-static-set-yurt-hub -n kube-system
```

### 4. 应用 Cluster 注解

安装后需要为 Cluster CR 添加 edge-runtime 注解：

```bash
# 方式一：使用 kubectl 手动添加
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt \
  --overwrite

# 方式二：使用提供的助手脚本
kubectl get configmap openyurt-cluster-config -n kube-system \
  -o jsonpath='{.data.apply-annotation\.sh}' | bash
```

### 5. 验证配置

```bash
# 检查 Cluster CR 注解
kubectl get cluster host -o yaml | grep edge-runtime

# 测试 join-token 生成（假设 APIServer 运行在 localhost:8080）
curl "http://localhost:8080/oapis/infra.theriseunion.io/v1alpha1/join-token?nodeName=test-node"
```

## 配置说明

### 核心配置

| 参数 | 描述 | 默认值 | 是否必需 |
|------|------|--------|---------|
| `openyurt.apiServer.endpoint` | Kubernetes API Server 地址 | `""` | **是** |
| `cluster.name` | 集群名称 | `host` | 否 |
| `cluster.edgeRuntime` | 边缘运行时类型 | `openyurt` | 否 |
| `namespace` | 安装命名空间 | `kube-system` | 否 |

### YurtHub 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `configMap.data.yurtHubImage` | YurtHub 镜像 | `openyurt/yurthub:v1.5.0` |
| `configMap.data.yurtHubPort` | YurtHub 服务端口 | `10261` |
| `configMap.data.yurtHubProxyPort` | YurtHub 代理端口 | `10267` |
| `configMap.data.enableYurtHubHttps` | 启用 HTTPS | `true` |
| `configMap.data.workingMode` | 工作模式 | `edge` |

### 证书配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `openyurt.certificates.organization` | 证书组织 | `system:nodes` |
| `openyurt.certificates.validityDays` | 证书有效期（天） | `365` |

## 使用示例

### 示例 1: 基本部署

```bash
helm install openyurt-config . --namespace kube-system \
  --set openyurt.apiServer.endpoint=https://192.168.1.102:6443
```

### 示例 2: 自定义 YurtHub 镜像

```bash
helm install openyurt-config . --namespace kube-system \
  --set openyurt.apiServer.endpoint=https://k8s-api.example.com:6443 \
  --set configMap.data.yurtHubImage=myregistry/yurthub:v1.5.0
```

### 示例 3: 使用自定义 values 文件

创建 `my-values.yaml`:

```yaml
cluster:
  name: production-cluster

openyurt:
  apiServer:
    endpoint: "https://prod-k8s.example.com:6443"

  yurtHub:
    serverAddr: "https://prod-k8s.example.com:6443"

configMap:
  data:
    yurtHubImage: "myregistry/yurthub:v1.5.0"
```

安装:

```bash
helm install openyurt-config . --namespace kube-system -f my-values.yaml
```

## 升级

```bash
# 更新配置
helm upgrade openyurt-config . --namespace kube-system \
  --set openyurt.apiServer.endpoint=https://new-api-server:6443
```

## 卸载

```bash
# 卸载 Chart（保留 ConfigMap）
helm uninstall openyurt-config --namespace kube-system

# 如需删除 ConfigMap
kubectl delete configmap yurt-static-set-yurt-hub -n kube-system
kubectl delete configmap openyurt-cluster-config -n kube-system
```

## 故障排查

### 问题 1: ConfigMap 未创建

**症状**: `kubectl get cm yurt-static-set-yurt-hub -n kube-system` 返回 NotFound

**解决方案**:
1. 检查 Helm release 状态: `helm status openyurt-config -n kube-system`
2. 查看 Helm 日志: `helm get notes openyurt-config -n kube-system`
3. 验证权限: 确保有权限在 kube-system 命名空间创建 ConfigMap

### 问题 2: join-token API 返回错误

**症状**: API 返回 "failed to get ConfigMap kube-system/yurt-static-set-yurt-hub"

**解决方案**:
1. 确认 ConfigMap 存在: `kubectl get cm yurt-static-set-yurt-hub -n kube-system`
2. 检查 ConfigMap 内容: `kubectl describe cm yurt-static-set-yurt-hub -n kube-system`
3. 验证 API Server 地址正确: `kubectl get cm yurt-static-set-yurt-hub -n kube-system -o yaml | grep server-addr`

### 问题 3: Cluster CR 缺少注解

**症状**: join-token API 返回 "edge runtime not configured"

**解决方案**:
```bash
# 手动添加注解
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt \
  --overwrite

# 验证
kubectl get cluster host -o jsonpath='{.metadata.annotations.cluster\.theriseunion\.io/edge-runtime}'
```

## 集成到 deploy.sh

可以修改 `edge-installer/deploy.sh` 脚本，自动部署 OpenYurt 配置：

```bash
# 在 deploy.sh 中添加
if [ "$EDGE_RUNTIME" = "openyurt" ]; then
  echo "Deploying OpenYurt configuration..."
  helm upgrade --install openyurt-config ./openyurt-config \
    --namespace kube-system \
    --set openyurt.apiServer.endpoint="$API_SERVER_ENDPOINT" \
    --wait
fi
```

## 相关文档

- [OpenYurt 安装指南](../OPENYURT-SETUP.md)
- [Edge Platform 部署文档](../DEPLOY.md)
- [OpenYurt 官方文档](https://openyurt.io/docs/)

## 许可证

本项目采用与主项目相同的许可证。
