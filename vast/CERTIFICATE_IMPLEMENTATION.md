# 证书管理实现说明

本文档说明 apiserver 和 controller 组件如何使用 Helm 内置函数方式生成和管理证书。

## 实现方式

两个组件都采用了 **Helm 内置函数方式**（方案3）来生成证书：
- 使用 `genCA` 和 `genSignedCert` 函数
- 通过 pre-install hook 创建 Secret
- 在 Deployment 中自动挂载证书

## APIServer 组件

### 证书生成函数

位置：`vast/charts/apiserver/templates/_helpers.tpl`

```yaml
{{- define "apiserver.genCerts" -}}
# 生成包含以下 SAN 的证书：
# - <fullname>.<namespace>.svc.cluster.local
# - <fullname>.<namespace>.svc
# - <fullname>
# - 127.0.0.1
# - localhost
# - 自定义 additionalHosts
{{- end }}
```

### Secret 模板

位置：`vast/charts/apiserver/templates/secret.yaml`

- 使用 pre-install,pre-upgrade hook
- 自动生成包含 `tls.crt`, `tls.key`, `ca.crt` 的 Secret
- 仅在 `cert.create=true` 时创建

### 证书挂载

位置：`vast/charts/apiserver/templates/apiserver.yaml`

- 条件挂载：仅在 `config.server.tls.enabled=true` 且 `cert.create=true` 时挂载
- 挂载路径：`/tmp/k8s-webhook-server/serving-certs`
- 包含文件：`tls.crt`, `tls.key`

### 配置示例

```yaml
# values.yaml
cert:
  secretName: ""  # 自动生成：<release-name>-apiserver-cert
  create: true    # 启用自动生成
  validityDays: 3650  # 证书有效期（天）
  additionalHosts: []  # 额外的 SAN

config:
  server:
    tls:
      enabled: true
      certFile: "/tmp/k8s-webhook-server/serving-certs/tls.crt"
      keyFile: "/tmp/k8s-webhook-server/serving-certs/tls.key"
```

## Controller 组件

### 证书生成函数

位置：`vast/charts/controller/templates/_helpers.tpl`

```yaml
{{- define "controller.webhook.genCerts" -}}
# 生成包含以下 SAN 的证书：
# - <webhook-service>.<namespace>.svc.cluster.local
# - <webhook-service>.<namespace>.svc
# - <webhook-service>
# - 127.0.0.1
# - localhost
# - 自定义 additionalHosts
{{- end }}
```

### Secret 模板

位置：`vast/charts/controller/templates/secret.yaml`

- 使用 pre-install,pre-upgrade hook
- 自动生成包含 `tls.crt`, `tls.key`, `ca.crt` 的 Secret
- 仅在 `webhook.enabled=true` 且 `webhook.cert.create=true` 时创建

### 证书挂载

位置：`vast/charts/controller/templates/manager.yaml`

- 条件挂载：仅在 `webhook.enabled=true` 且 `webhook.cert.create=true` 时挂载
- 挂载路径：`/tmp/k8s-webhook-server/serving-certs`（可配置）
- 包含文件：`tls.crt`, `tls.key`

### Webhook 配置

位置：`vast/charts/controller/templates/webhook.yaml`

- **已移除 cert-manager 相关配置**
- 不再包含 `cert-manager.io/inject-ca-from` 注解
- Webhook 配置直接使用生成的证书

### 配置示例

```yaml
# values.yaml
webhook:
  enabled: true
  server:
    port: 9443
    host: "0.0.0.0"
    certDir: "/tmp/k8s-webhook-server/serving-certs"
  cert:
    secretName: ""  # 自动生成：<release-name>-controller-webhook-cert
    create: true    # 启用自动生成
    validityDays: 3650  # 证书有效期（天）
    additionalHosts: []  # 额外的 SAN
```

## 主要变更

### 1. 移除 cert-manager 支持

- ✅ 从 `webhook.yaml` 中移除了 `cert-manager.io/inject-ca-from` 注解
- ✅ 从 `values.yaml` 中移除了 `certManagerAnnotation` 配置项

### 2. 添加 Helm 内置证书生成

- ✅ 在 `_helpers.tpl` 中添加了证书生成函数
- ✅ 创建了 `secret.yaml` 模板（pre-install hook）
- ✅ 更新了 Deployment 模板以挂载证书

### 3. 配置优化

- ✅ 使用条件渲染，按需创建和挂载证书
- ✅ 支持自定义证书有效期
- ✅ 支持添加额外的 SAN（Subject Alternative Names）
- ✅ 自动生成 Secret 名称

## 证书文件结构

生成的 Secret 包含以下键：

- `tls.crt` - 服务器证书
- `tls.key` - 私钥
- `ca.crt` - CA 证书（用于验证）

## 证书 SAN 列表

### APIServer
- `<release-name>-apiserver.<namespace>.svc.cluster.local`
- `<release-name>-apiserver.<namespace>.svc`
- `<release-name>-apiserver`
- `127.0.0.1`
- `localhost`
- 自定义 `additionalHosts`

### Controller Webhook
- `<release-name>-controller-webhook-service.<namespace>.svc.cluster.local`
- `<release-name>-controller-webhook-service.<namespace>.svc`
- `<release-name>-controller-webhook-service`
- `127.0.0.1`
- `localhost`
- 自定义 `additionalHosts`

## 使用示例

### 启用 APIServer TLS

```yaml
apiserver:
  cert:
    create: true
  config:
    server:
      tls:
        enabled: true
```

### 启用 Controller Webhook 证书

```yaml
controller:
  webhook:
    enabled: true
    cert:
      create: true
```

### 自定义证书有效期

```yaml
apiserver:
  cert:
    validityDays: 730  # 2年

controller:
  webhook:
    cert:
      validityDays: 730  # 2年
```

### 添加额外的 SAN

```yaml
apiserver:
  cert:
    additionalHosts:
      - "api.example.com"
      - "10.0.0.1"

controller:
  webhook:
    cert:
      additionalHosts:
      - "webhook.example.com"
```

## 验证

### 检查证书 Secret

```bash
# APIServer
kubectl get secret <release-name>-apiserver-cert -n <namespace>

# Controller
kubectl get secret <release-name>-controller-webhook-cert -n <namespace>
```

### 检查证书挂载

```bash
# 检查 APIServer Pod
kubectl exec -n <namespace> <apiserver-pod> -- ls -la /tmp/k8s-webhook-server/serving-certs

# 检查 Controller Pod
kubectl exec -n <namespace> <controller-pod> -- ls -la /tmp/k8s-webhook-server/serving-certs
```

### 验证证书内容

```bash
# 查看证书信息
kubectl get secret <release-name>-apiserver-cert -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## 注意事项

1. **证书自动生成**：每次 `helm upgrade` 时，如果 Secret 不存在，会重新生成
2. **证书有效期**：默认 3650 天（10年），可根据需要调整
3. **Hook 策略**：使用 `before-hook-creation` 策略，确保升级时重新生成证书
4. **条件渲染**：证书仅在相应配置启用时创建和挂载

## 相关文件

- `vast/charts/apiserver/templates/_helpers.tpl` - APIServer 证书生成函数
- `vast/charts/apiserver/templates/secret.yaml` - APIServer 证书 Secret
- `vast/charts/apiserver/templates/apiserver.yaml` - APIServer Deployment
- `vast/charts/controller/templates/_helpers.tpl` - Controller 证书生成函数
- `vast/charts/controller/templates/secret.yaml` - Controller 证书 Secret
- `vast/charts/controller/templates/manager.yaml` - Controller Deployment
- `vast/charts/controller/templates/webhook.yaml` - Webhook 配置（已移除 cert-manager）

