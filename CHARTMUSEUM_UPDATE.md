# ChartMuseum 镜像更新操作指南

## 问题说明

1. **edge-logs Chart 不在 ChartMuseum 中**
   - ChartMuseum 使用的镜像 `edge/edge-museum:main` 是在没有 edge-logs Chart 之前构建的
   - 导致 edge-logs Component 无法从 ChartMuseum 下载 Chart（404 错误）
   - ClickHouse 等服务也就无法安装

2. **ClickHouse 没有安装**
   - 这是 edge-logs Chart 无法安装的连锁反应

## 解决方案

需要重新构建 ChartMuseum 镜像，包含所有 Charts（特别是 edge-logs），然后更新部署。

## 测试环境操作步骤

在测试节点 (119.8.182.199) 上执行：

### 步骤 1：同步最新代码

```bash
cd /root/edge-installer
git pull
# 或者重新 rsync
```

### 步骤 2：更新 ChartMuseum 镜像

```bash
# 方式1：使用 Makefile（推荐）
make update-chartmuseum

# 方式2：使用脚本
./update-chartmuseum.sh

# 方式3：手动执行
make package-charts
make docker-build-museum
make docker-push-museum
```

### 步骤 3：更新 edge-platform

等待 ChartMuseum 镜像构建和推送完成后：

```bash
# 等待 ChartMuseum Pod 使用新镜像
kubectl rollout restart deployment/chartmuseum -n edge-system

# 等待 Pod 重启完成
kubectl rollout status deployment/chartmuseum -n edge-system

# 更新 edge-platform
helm upgrade edge-platform ./edge-controller --namespace edge-system --set global.imageRegistry=quanzhenglong.com

# 或者如果不需要更新 registry
helm upgrade edge-platform ./edge-controller --namespace edge-system
```

### 步骤 4：验证安装

```bash
# 等待所有组件安装完成
kubectl get component -A

# 检查 edge-logs Component 状态
kubectl get component edge-logs -n logging-system

# 检查 logging-system namespace 中的 Pod
kubectl get pods -n logging-system

# 应该看到以下 Pod：
# - clickhouse-xxx (ClickHouse 数据库)
# - otelcollector-xxx (OTEL Collector)
# - apiserver-xxx (Logs API Server)
# - ilogtail-xxx (iLogtail 采集器，DaemonSet)
```

## 预期结果

完成后，`logging-system` namespace 应该有以下 Pod：

```bash
$ kubectl get pods -n logging-system
NAME                              READY   STATUS    RESTARTS   AGE
apiserver-xxx                     1/1     Running   0          XXm
clickhouse-0                       1/1     Running   0          XXm
ilogtail-xxx                      1/1     Running   0          XXm
otelcollector-xxx                  1/1     Running   0          XXm
```

## 故障排查

### 如果 edge-logs Component 仍然失败

```bash
# 查看 Component 状态
kubectl describe component edge-logs -n logging-system

# 查看 controller 日志
kubectl logs deployment/controller -n edge-system | grep edge-logs

# 验证 edge-logs Chart 在 ChartMuseum 中
kubectl exec -n edge-system deployment/chartmuseum -- ls -la /charts/edge-logs*
```

### 如果 ClickHouse Pod 启动失败

```bash
# 查看 ClickHouse Pod 日志
kubectl logs -n logging-system statefulset/clickhouse-0

# 查看 ClickHouse 配置
kubectl get configmap -n logging-system clickhouse-config -o yaml

# 检查 PVC 状态
kubectl get pvc -n logging-system
```

## 自动化脚本

为了简化操作，提供了 `update-chartmuseum.sh` 脚本，它会执行以下步骤：

1. 打包所有 Helm Charts
2. 构建 ChartMuseum 镜像
3. 推送镜像到 registry
4. 更新 Kubernetes deployment
5. 验证 Pod 状态

使用方法：

```bash
cd /root/edge-installer
./update-chartmuseum.sh
```

## 注意事项

1. **镜像 tag**：ChartMuseum 镜像使用 `quanzhenglong.com/edge/edge-museum:main`
2. **构建时间**：首次构建可能需要 5-10 分钟（取决于网络速度）
3. **镜像大小**：完整的 ChartMuseum 镜像较大（包含所有 Charts），推送可能需要时间
4. **依赖**：需要 Docker 和 kubectl 可用

## 本地开发环境

在本地开发环境中，如果需要测试：

```bash
# 1. 打包 Charts
make package-charts

# 2. 本地测试 ChartMuseum
make docker-build-museum MUSEUM_IMG=quanzhenglong.com/edge/edge-museum:test

# 3. 本地运行 ChartMuseum（用于测试）
docker run -d --rm -p 8080:8080 \
  -v $(pwd)/bin/_output:/charts \
  ghcr.io/helm/chartmuseum:v0.16.3 \
  --storage local --storage-local-rootdir /charts

# 4. 测试访问
curl http://localhost:8080/api/charts
```
