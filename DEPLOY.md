# Edge Platform 部署指南

## 快速部署

使用 Helm 直接部署 Edge Platform 的三个核心组件。

### 前置要求

- Kubernetes 集群 (v1.24+)
- Helm 3.8+
- kubectl 配置好并能访问集群

### 一键部署

```bash
# 使用默认配置部署到指定集群
KUBECONFIG_PATH=~/.kube/116.63.161.198.config ./deploy.sh
```

### 手动 Helm 部署

#### 1. 创建命名空间

```bash
kubectl create namespace edge-system
```

#### 2. 部署 Controller

```bash
helm install edge-controller ./charts/edge-controller \
  --namespace edge-system \
  --set image.repository=quanzhenglong.com/edge/edge-controller \
  --set image.tag=main
```

#### 3. 部署 API Server

```bash
helm install edge-apiserver ./charts/edge-apiserver \
  --namespace edge-system \
  --set image.repository=quanzhenglong.com/edge/edge-apiserver \
  --set image.tag=main
```

#### 4. 部署 Console

```bash
helm install edge-console ./charts/edge-console \
  --namespace edge-system \
  --set image.repository=quanzhenglong.com/edge/edge-console \
  --set image.tag=main \
  --set env[0].name=NEXT_PUBLIC_API_BASE_URL \
  --set env[0].value=http://edge-apiserver:8080
```

### 自定义部署

#### 使用不同的镜像仓库和标签

```bash
# 设置环境变量
export REGISTRY=your-registry.com/edge
export TAG=v1.0.0
export NAMESPACE=my-namespace
export KUBECONFIG_PATH=/path/to/kubeconfig
export PULL_POLICY=Always  # Always, IfNotPresent, Never

# 执行部署
./deploy.sh
```

### 镜像拉取策略配置

- **开发环境**：`PULL_POLICY=Always` - 总是拉取最新镜像
- **生产环境**：`PULL_POLICY=IfNotPresent` - 仅在镜像不存在时拉取
- **离线环境**：`PULL_POLICY=Never` - 从不拉取，使用本地镜像

#### 使用 values 文件

创建自定义 values 文件：

```yaml
# custom-values.yaml
image:
  repository: quanzhenglong.com/edge/edge-apiserver
  tag: main
  pullPolicy: Always

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 256Mi
```

使用自定义 values 部署：

```bash
helm install edge-apiserver ./charts/edge-apiserver \
  --namespace edge-system \
  -f custom-values.yaml
```

### 验证部署

```bash
# 查看所有 Pod
kubectl get pods -n edge-system

# 查看服务
kubectl get svc -n edge-system

# 查看日志
kubectl logs -n edge-system deployment/edge-controller
kubectl logs -n edge-system deployment/edge-apiserver
kubectl logs -n edge-system deployment/edge-console
```

### 安装后配置

#### ⚠️ 重要: 配置边缘运行时

部署完成后,**必须**为集群配置边缘运行时类型才能添加边缘节点。

**方式一: 通过 Web Console 配置 (推荐)**

1. 访问 Console: http://localhost:3000
2. 导航至: **集群管理** → 选择集群 → **基本信息**
3. 找到 **边缘运行时** 字段,点击编辑图标
4. 选择 `openyurt` 或 `kubeedge`
5. 保存配置

**方式二: 通过 kubectl 配置**

```bash
# 为 host 集群配置 OpenYurt 运行时
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=openyurt

# 或配置 KubeEdge 运行时
kubectl annotate cluster host \
  cluster.theriseunion.io/edge-runtime=kubeedge
```

**验证配置:**

```bash
# 检查边缘运行时配置
kubectl get cluster host -o yaml | grep edge-runtime

# 输出示例:
# cluster.theriseunion.io/edge-runtime: openyurt
```

配置完成后,即可通过 Console 获取节点加入令牌并添加边缘节点。

### 访问服务

#### 端口转发

```bash
# API Server
kubectl port-forward -n edge-system svc/edge-apiserver 8080:8080

# Console
kubectl port-forward -n edge-system svc/edge-console 3000:3000
```

访问：
- API Server: http://localhost:8080
- Console: http://localhost:3000

### 卸载

```bash
# 卸载所有组件
helm uninstall edge-console -n edge-system
helm uninstall edge-apiserver -n edge-system
helm uninstall edge-controller -n edge-system

# 删除命名空间（可选）
kubectl delete namespace edge-system
```

## 生产环境部署

### 使用 Ingress

为 Console 配置 Ingress：

```yaml
# console-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: edge-console
  namespace: edge-system
spec:
  ingressClassName: nginx
  rules:
  - host: edge.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: edge-console
            port:
              number: 3000
```

### 配置持久化存储

如需持久化存储，在部署时指定 StorageClass：

```bash
helm install edge-apiserver ./charts/edge-apiserver \
  --namespace edge-system \
  --set persistence.enabled=true \
  --set persistence.storageClass=your-storage-class
```

### 高可用部署

增加副本数：

```bash
helm upgrade edge-apiserver ./charts/edge-apiserver \
  --namespace edge-system \
  --set replicaCount=3
```

## 故障排查

### 镜像拉取失败

如果镜像拉取失败，确认：

1. 镜像仓库地址正确
2. 镜像标签存在
3. 集群节点能访问镜像仓库

### Pod 启动失败

查看 Pod 详细信息：

```bash
kubectl describe pod -n edge-system <pod-name>
kubectl logs -n edge-system <pod-name>
```

### 服务连接问题

检查服务端点：

```bash
kubectl get endpoints -n edge-system
```

## 未来规划

未来我们将迁移到类似 Kubernetes ks-installer 的模式：

1. 使用 Operator 模式管理安装
2. 通过 CRD 配置所有组件
3. 支持更复杂的部署场景
4. 提供 Web 界面的安装向导

目前的 Helm 部署方式简单直接，适合快速部署和测试。