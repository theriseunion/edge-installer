# 证书管理方案总结

本文档总结了项目中各组件使用的证书管理方式，为 vast 组件实现证书管理提供参考。

## 证书管理方式对比

### 1. Hami 组件 - 使用 Helm Hook Job 创建证书

**特点**：
- 使用 `kube-webhook-certgen` 工具自动生成证书
- 通过 Helm Hook 在安装前创建证书，安装后更新 webhook 配置

**实现方式**：

#### 证书创建 Job (pre-install hook)
```yaml
# job-createSecret.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "hami-vgpu.fullname" . }}-admission-create
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      containers:
        - name: create
          image: {{ .Values.scheduler.patch.image }}
          args:
            - create
            - --cert-name=tls.crt
            - --key-name=tls.key
            - --host={{ printf "%s.%s.svc,127.0.0.1" (include "hami-vgpu.scheduler" .) (include "hami-vgpu.namespace" .) }}
            - --namespace={{ include "hami-vgpu.namespace" . }}
            - --secret-name={{ include "hami-vgpu.scheduler.tls" . }}
```

#### Webhook 更新 Job (post-install hook)
```yaml
# job-patchWebhook.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "hami-vgpu.fullname" . }}-admission-patch
  annotations:
    "helm.sh/hook": post-install,post-upgrade
spec:
  template:
    spec:
      containers:
        - name: patch
          image: {{ .Values.scheduler.patch.image }}
          args:
            - patch
            - --webhook-name={{ include "hami-vgpu.scheduler.webhook" . }}
            - --namespace={{ include "hami-vgpu.namespace" . }}
            - --secret-name={{ include "hami-vgpu.scheduler.tls" . }}
```

#### 证书挂载
```yaml
# deployment.yaml
volumeMounts:
  - name: tls-config
    mountPath: /tls
volumes:
  - name: tls-config
    secret:
      secretName: {{ template "hami-vgpu.scheduler.tls" . }}
```

**配置示例**：
```yaml
# values.yaml
scheduler:
  patch:
    image: docker.io/jettech/kube-webhook-certgen:v1.5.2
    imageNew: liangjw/kube-webhook-certgen:v1.1.1
    imagePullPolicy: IfNotPresent
    runAsUser: 2000
```

**优点**：
- 自动化程度高，无需手动创建证书
- 支持自动更新 webhook 配置中的 CA bundle
- 适合 webhook 场景

**缺点**：
- 需要额外的 Job 资源
- 依赖外部工具镜像

---

### 2. KubeEdge 组件 - 使用 Helm 内置函数生成证书

**特点**：
- 使用 Helm 的 `genCA` 和 `genSignedCert` 函数
- 在模板中直接生成证书内容

**实现方式**：

#### 证书生成函数
```yaml
# _helpers.tpl
{{- define "kubeedge.genCloudCoreCerts" -}}
{{- $altNames := list }}
{{- $altNames = append $altNames (printf "cloudcore.%s.svc.cluster.local" .Release.Namespace) }}
{{- $altNames = append $altNames (printf "cloudcore.%s.svc" .Release.Namespace) }}
{{- $altNames = append $altNames "cloudcore" }}

{{- $ca := genCA "cloudcore-ca" 3650 }}
{{- $cert := genSignedCert "cloudcore" nil $altNames 3650 $ca }}

streamCA.crt: {{ $ca.Cert | b64enc }}
stream.crt: {{ $cert.Cert | b64enc }}
stream.key: {{ $cert.Key | b64enc }}
{{- end }}
```

#### Secret 创建 (pre-install hook)
```yaml
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudcore
  annotations:
    "helm.sh/hook": "pre-install"
    "helm.sh/hook-delete-policy": "before-hook-creation"
type: Opaque
data:
{{ ( include "kubeedge.genCloudCoreCerts" . ) | indent 2 }}
```

#### 证书挂载（使用 items 指定文件路径）
```yaml
# deployment.yaml
volumeMounts:
  - name: certs
    mountPath: /etc/kubeedge
volumes:
  - name: certs
    secret:
      secretName: cloudcore
      items:
        - key: stream.crt
          path: certs/stream.crt
        - key: stream.key
          path: certs/stream.key
        - key: streamCA.crt
          path: ca/streamCA.crt
```

**优点**：
- 无需外部工具，纯 Helm 实现
- 证书内容直接嵌入模板
- 适合简单的证书需求

**缺点**：
- 证书内容在模板中可见（虽然已 base64 编码）
- 每次 helm upgrade 都会重新生成证书
- 不适合需要长期有效证书的场景

---

### 3. APIServer 组件 - 配置已定义但未启用

**特点**：
- 证书配置结构已定义，但实际使用被注释
- 支持通过 values.yaml 配置证书路径

**实现方式**：

#### 配置结构
```yaml
# values.yaml
cert:
  secretName: apiserver-cert
  create: false

config:
  server:
    tls:
      enabled: true
      certFile: "/tmp/k8s-webhook-server/serving-certs/tls.crt"
      keyFile: "/tmp/k8s-webhook-server/serving-certs/tls.key"
```

#### 挂载（已注释）
```yaml
# apiserver.yaml (注释掉的部分)
# volumeMounts:
#   - name: cert
#     mountPath: /tmp/k8s-webhook-server/serving-certs
#     readOnly: true
# volumes:
#   - name: cert
#     secret:
#       secretName: {{ .Values.cert.secretName }}
```

**优点**：
- 结构清晰，易于扩展
- 支持手动管理证书

**缺点**：
- 需要手动创建证书 Secret
- 当前未启用

---

### 4. Controller 组件 - 支持多种证书管理方式

**特点**：
- 支持 cert-manager 自动管理
- 支持手动创建证书
- 支持条件渲染

**实现方式**：

#### 配置结构
```yaml
# values.yaml
webhook:
  enabled: true
  cert:
    secretName: ""  # 为空则自动生成
    create: false
    certManagerAnnotation: ""  # 格式：namespace/secret-name
```

#### 条件挂载
```yaml
# manager.yaml
volumeMounts:
  {{- if and .Values.webhook.enabled .Values.webhook.cert.create }}
  - name: cert
    mountPath: {{ include "controller.webhook.certDir" . }}
    readOnly: true
  {{- end }}
volumes:
  {{- if and .Values.webhook.enabled .Values.webhook.cert.create }}
  - name: cert
    secret:
      secretName: {{ include "controller.webhook.certSecretName" . }}
      defaultMode: 420
  {{- end }}
```

#### cert-manager 集成
```yaml
# webhook.yaml
metadata:
  {{- if .Values.webhook.cert.certManagerAnnotation }}
  annotations:
    cert-manager.io/inject-ca-from: {{ .Values.webhook.cert.certManagerAnnotation }}
  {{- end }}
```

**优点**：
- 灵活性高，支持多种证书管理方式
- 支持 cert-manager 自动管理
- 条件渲染，按需挂载

**缺点**：
- 需要额外配置 cert-manager（如果使用）

---

## 推荐方案

根据 vast 组件的需求，推荐以下方案：

### 方案 1：使用 Helm Hook Job（推荐用于 Webhook）

**适用场景**：
- Webhook 需要自动证书管理
- 需要自动更新 webhook 配置中的 CA bundle

**实现步骤**：
1. 创建 pre-install Job 用于生成证书
2. 创建 post-install Job 用于更新 webhook 配置
3. 在 Deployment 中挂载证书 Secret

### 方案 2：使用 cert-manager（推荐用于生产环境）

**适用场景**：
- 生产环境需要自动续期
- 需要符合企业安全策略

**实现步骤**：
1. 配置 cert-manager Certificate 资源
2. 在 webhook 配置中添加 cert-manager 注解
3. 在 Deployment 中挂载证书 Secret

### 方案 3：使用 Helm 内置函数（推荐用于开发/测试）

**适用场景**：
- 开发/测试环境
- 简单的证书需求

**实现步骤**：
1. 在 `_helpers.tpl` 中创建证书生成函数
2. 创建 pre-install Secret
3. 在 Deployment 中挂载证书 Secret

## 证书路径规范

项目中常见的证书挂载路径：

- `/tmp/k8s-webhook-server/serving-certs` - Webhook 服务器证书（controller, apiserver）
- `/tls` - Hami scheduler 证书
- `/etc/kubeedge` - KubeEdge 证书

证书文件名规范：
- `tls.crt` - 证书文件
- `tls.key` - 私钥文件
- `ca.crt` 或 `streamCA.crt` - CA 证书（如需要）

## 最佳实践

1. **使用模板函数生成 Secret 名称**：
   ```yaml
   {{- define "component.certSecretName" -}}
   {{- printf "%s-cert" (include "component.fullname" .) }}
   {{- end }}
   ```

2. **使用条件渲染**：
   ```yaml
   {{- if .Values.cert.create }}
   # 证书相关配置
   {{- end }}
   ```

3. **支持 cert-manager**：
   ```yaml
   {{- if .Values.cert.certManagerAnnotation }}
   annotations:
     cert-manager.io/inject-ca-from: {{ .Values.cert.certManagerAnnotation }}
   {{- end }}
   ```

4. **使用 Helm Hook 管理证书生命周期**：
   ```yaml
   annotations:
     "helm.sh/hook": pre-install,pre-upgrade
     "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
   ```

5. **提供清晰的配置选项**：
   ```yaml
   cert:
     secretName: ""  # 自动生成或手动指定
     create: false   # 是否自动创建
     certManagerAnnotation: ""  # cert-manager 集成
   ```

## 相关文件

- `vast/charts/hami/templates/scheduler/job-patch/job-createSecret.yaml` - Hami 证书创建 Job
- `vast/charts/hami/templates/scheduler/job-patch/job-patchWebhook.yaml` - Hami webhook 更新 Job
- `kubeedge/templates/secret.yaml` - KubeEdge 证书 Secret
- `kubeedge/templates/_helpers.tpl` - KubeEdge 证书生成函数
- `vast/charts/controller/templates/webhook.yaml` - Controller webhook 配置
- `vast/charts/apiserver/values.yaml` - APIServer 证书配置

