# OpenYurt 1.6 镜像列表

本文档列出 OpenYurt 1.6 所需的所有容器镜像及其同步到私有镜像仓库的方法。

## 目录

- [镜像列表](#镜像列表)
- [镜像同步](#镜像同步)
- [镜像配置](#镜像配置)
- [镜像验证](#镜像验证)

## 镜像列表

### 核心组件镜像

| 组件 | 公共镜像 | 私有镜像 | 说明 |
|------|---------|---------|------|
| yurt-manager | `openyurt/yurt-manager:v1.6.0` | `quanzhenglong.com/edge/yurt-manager:v1.6.0` | OpenYurt 核心控制器 |
| yurthub | `openyurt/yurthub:v1.6.0` | `quanzhenglong.com/edge/yurthub:v1.6.0` | 边缘节点代理组件 |
| raven-agent | `openyurt/raven-agent:v0.4.1` | `quanzhenglong.com/edge/raven-agent:v0.4.1` | 边缘网络通信组件（可选） |

### 支持的版本

| OpenYurt 版本 | 发布日期 | 状态 | 镜像标签 |
|--------------|---------|------|---------|
| v1.6.0 | 2025-01-07 | 稳定 | v1.6.0 |
| v1.6.1 | TBD | 计划中 | v1.6.1 |
| v1.6.2 | TBD | 计划中 | v1.6.2 |

### 架构支持

所有镜像支持以下架构：

- `linux/amd64` (x86_64)
- `linux/arm64` (aarch64)

## 镜像同步

### 前置要求

1. **安装 skopeo**

   ```bash
   # macOS
   brew install skopeo

   # Ubuntu/Debian
   sudo apt-get install skopeo

   # CentOS/RHEL
   sudo yum install skopeo
   ```

2. **私有镜像仓库认证信息**

   - 仓库地址: `quanzhenglong.com`
   - 用户名: `edge_admin`
   - 密码: 请从管理员获取

### 方式一：使用同步脚本（推荐）

```bash
# 1. 设置镜像仓库密码
export REGISTRY_PASSWORD=YOUR_PASSWORD

# 2. 运行同步脚本（同步所有版本）
./sync-images.sh

# 3. 仅同步指定版本
./sync-images.sh -v "v1.6.0"

# 4. 查看将要执行的命令（dry-run 模式）
./sync-images.sh --dry-run

# 5. 同步所有版本包括 raven-agent
./sync-images.sh -w YOUR_PASSWORD
```

### 方式二：手动同步

```bash
# 设置变量
REGISTRY_USERNAME=edge_admin
REGISTRY_PASSWORD=YOUR_PASSWORD
PRIVATE_REGISTRY=quanzhenglong.com/edge

# 1. 同步 yurt-manager
skopeo copy --insecure-policy \
  --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
  --multi-arch all \
  docker://openyurt/yurt-manager:v1.6.0 \
  docker://$PRIVATE_REGISTRY/yurt-manager:v1.6.0

# 2. 同步 yurthub
skopeo copy --insecure-policy \
  --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
  --multi-arch all \
  docker://openyurt/yurthub:v1.6.0 \
  docker://$PRIVATE_REGISTRY/yurthub:v1.6.0

# 3. 同步 raven-agent
skopeo copy --insecure-policy \
  --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
  --multi-arch all \
  docker://openyurt/raven-agent:v0.4.1 \
  docker://$PRIVATE_REGISTRY/raven-agent:v0.4.1

# 4. 同步 latest 标签
skopeo copy --insecure-policy \
  --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
  --multi-arch all \
  docker://openyurt/yurt-manager:v1.6.0 \
  docker://$PRIVATE_REGISTRY/yurt-manager:latest

skopeo copy --insecure-policy \
  --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
  --multi-arch all \
  docker://openyurt/yurthub:v1.6.0 \
  docker://$PRIVATE_REGISTRY/yurthub:latest

skopeo copy --insecure-policy \
  --dest-creds "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" \
  --multi-arch all \
  docker://openyurt/raven-agent:v0.4.1 \
  docker://$PRIVATE_REGISTRY/raven-agent:latest
```

## 镜像配置

### Helm Values 配置

私有镜像仓库的配置已预先设置在 Helm values 文件中：

**yurt-manager-values.yaml:**
```yaml
image:
  repository: quanzhenglong.com/edge/yurt-manager
  tag: v1.6.0
  pullPolicy: IfNotPresent
```

**yurthub-values.yaml:**
```yaml
image:
  repository: quanzhenglong.com/edge/yurthub
  tag: v1.6.0
  pullPolicy: IfNotPresent
```

**raven-agent-values.yaml:**
```yaml
image:
  repository: quanzhenglong.com/edge/raven-agent
  tag: v0.4.1
  pullPolicy: IfNotPresent
```

### ImagePullSecrets 配置

如果私有镜像仓库需要认证，创建 ImagePullSecret：

```bash
# 创建 secret
kubectl create secret docker-registry edge-registry \
  --docker-server=quanzhenglong.com \
  --docker-username=edge_admin \
  --docker-password=YOUR_PASSWORD \
  -n kube-system

# 在 values 文件中启用
imagePullSecrets:
  - name: edge-registry
```

### 切换到公共镜像

如果需要使用公共镜像，修改 values 文件：

```yaml
image:
  repository: openyurt/yurt-manager  # 改为公共镜像
  tag: v1.6.0
  pullPolicy: IfNotPresent
```

## 镜像验证

### 验证镜像已上传

```bash
# 查看 yurt-manager 可用标签
skopeo list-tags docker://quanzhenglong.com/edge/yurt-manager

# 查看 yurthub 可用标签
skopeo list-tags docker://quanzhenglong.com/edge/yurthub

# 查看 raven-agent 可用标签
skopeo list-tags docker://quanzhenglong.com/edge/raven-agent
```

### 检查镜像详细信息

```bash
# 查看镜像架构信息
skopeo inspect --raw docker://quanzhenglong.com/edge/yurt-manager:v1.6.0 | jq

# 查看镜像配置
skopeo inspect docker://quanzhenglong.com/edge/yurt-manager:v1.6.0
```

### 测试拉取镜像

```bash
# 使用 Docker 测试拉取
docker login quanzhenglong.com -u edge_admin -p YOUR_PASSWORD
docker pull quanzhenglong.com/edge/yurt-manager:v1.6.0

# 使用 crictl 测试拉取（在边缘节点上）
crictl pull quanzhenglong.com/edge/yurthub:v1.6.0
```

## 镜像大小参考

| 镜像 | 架构 | 压缩大小 | 解压大小 |
|------|------|---------|---------|
| yurt-manager:v1.6.0 | amd64 | ~50 MB | ~150 MB |
| yurt-manager:v1.6.0 | arm64 | ~48 MB | ~145 MB |
| yurthub:v1.6.0 | amd64 | ~40 MB | ~120 MB |
| yurthub:v1.6.0 | arm64 | ~38 MB | ~115 MB |
| raven-agent:v0.4.1 | amd64 | ~35 MB | ~100 MB |
| raven-agent:v0.4.1 | arm64 | ~33 MB | ~95 MB |

*注：实际大小可能因版本而异，以上数据仅供参考*

## 故障排除

### 问题 1: skopeo 同步失败

**错误信息:**
```
Error writing manifest: errors:
denied: requested access to the resource is denied
```

**解决方法:**
- 检查用户名和密码是否正确
- 确认账户有推送权限
- 检查镜像仓库地址是否正确

### 问题 2: 镜像拉取失败

**错误信息:**
```
Failed to pull image: pull access denied
```

**解决方法:**

1. 检查 ImagePullSecret 是否正确配置
2. 验证 secret 存在：
   ```bash
   kubectl get secret edge-registry -n kube-system
   ```
3. 检查 values 文件中的 imagePullSecrets 配置

### 问题 3: 多架构镜像同步不完整

**解决方法:**

使用 `--multi-arch all` 参数确保同步所有架构：

```bash
skopeo copy --multi-arch all \
  docker://openyurt/yurt-manager:v1.6.0 \
  docker://quanzhenglong.com/edge/yurt-manager:v1.6.0
```

### 问题 4: 网络超时

**解决方法:**

1. 使用代理：
   ```bash
   export HTTP_PROXY=http://proxy:port
   export HTTPS_PROXY=http://proxy:port
   ```

2. 增加超时时间：
   ```bash
   skopeo copy --command-timeout=10m ...
   ```

## 最佳实践

1. **版本管理**
   - 使用具体版本标签，避免使用 `latest`
   - 为每个版本创建备份标签

2. **镜像验证**
   - 同步后立即验证镜像完整性
   - 测试拉取确保可用性

3. **定期更新**
   - 关注 OpenYurt 新版本发布
   - 及时同步安全更新

4. **自动化**
   - 集成到 CI/CD 流程
   - 使用脚本自动化同步过程

5. **备份策略**
   - 保留多个版本以支持回滚
   - 定期清理不使用的旧版本

## 参考链接

- [OpenYurt 官方镜像](https://hub.docker.com/u/openyurt)
- [Skopeo 文档](https://github.com/containers/skopeo)
- [同步脚本](./sync-images.sh)
- [安装文档](./README.md)

## 更新历史

| 日期 | 版本 | 变更说明 |
|------|------|---------|
| 2025-01-15 | 1.0 | 初始版本，支持 OpenYurt 1.6.0 |
