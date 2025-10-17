# EdgeX Foundry Minnesota 镜像清单

## 概述

本文档列出了部署 EdgeX Foundry Minnesota 版本和 yurt-iot-dock 所需的所有镜像。

**总计**: 14个镜像

**同步脚本**: `./sync-images-to-registry.sh`

## 镜像列表

### 1. yurt-iot-dock (2个镜像)

| 源镜像 | 目标镜像 | 说明 |
|--------|----------|------|
| quanzhenglong.com/edge/yurt-iot-dock:v1.6.0-fixed | quanzhenglong.com/openyurt/yurt-iot-dock:v1.6.0-fixed | 修复版 yurt-iot-dock |
| quanzhenglong.com/edge/yurt-iot-dock:v1.6.0-fixed | quanzhenglong.com/openyurt/yurt-iot-dock:latest | 最新版标签 |

**说明**:
- v1.6.0-fixed 包含了 v1alpha1 Device API 注册的修复
- OpenYurt PlatformAdmin 控制器会自动使用 `latest` 标签

### 2. EdgeX 核心服务 (5个镜像)

| 源镜像 | 目标镜像 | 说明 |
|--------|----------|------|
| edgexfoundry/core-command:3.0.0 | quanzhenglong.com/edgexfoundry/core-command:3.0.0 | 设备命令服务 |
| edgexfoundry/core-metadata:3.0.0 | quanzhenglong.com/edgexfoundry/core-metadata:3.0.0 | 设备元数据管理 |
| edgexfoundry/core-data:3.0.0 | quanzhenglong.com/edgexfoundry/core-data:3.0.0 | 数据处理服务 |
| edgexfoundry/support-notifications:3.0.0 | quanzhenglong.com/edgexfoundry/support-notifications:3.0.0 | 通知支持服务 |
| edgexfoundry/support-scheduler:3.0.0 | quanzhenglong.com/edgexfoundry/support-scheduler:3.0.0 | 调度支持服务 |

### 3. EdgeX 设备服务 (4个镜像)

| 源镜像 | 目标镜像 | 说明 |
|--------|----------|------|
| edgexfoundry/device-virtual:3.0.0 | quanzhenglong.com/edgexfoundry/device-virtual:3.0.0 | 虚拟设备服务 |
| edgexfoundry/device-rest:3.0.0 | quanzhenglong.com/edgexfoundry/device-rest:3.0.0 | REST 设备服务 |
| edgexfoundry/device-mqtt:3.0.0 | quanzhenglong.com/edgexfoundry/device-mqtt:3.0.0 | MQTT 设备服务（可选）|
| edgexfoundry/device-modbus:3.0.0 | quanzhenglong.com/edgexfoundry/device-modbus:3.0.0 | Modbus 设备服务（可选）|

### 4. EdgeX 基础设施 (2个镜像)

| 源镜像 | 目标镜像 | 说明 |
|--------|----------|------|
| consul:1.15 | quanzhenglong.com/edgexfoundry/consul:1.15 | 配置中心 |
| redis:7.0-alpine | quanzhenglong.com/edgexfoundry/redis:7.0-alpine | 数据存储 |

### 5. EdgeX 配置引导 (1个镜像)

| 源镜像 | 目标镜像 | 说明 |
|--------|----------|------|
| edgexfoundry/core-common-config-bootstrapper:3.0.0 | quanzhenglong.com/edgexfoundry/core-common-config-bootstrapper:3.0.0 | 配置初始化 |

## 使用方法

### 同步所有镜像

```bash
# 设置密码
export REGISTRY_PASSWORD='your-password'

# 执行同步
./sync-images-to-registry.sh
```

### 查看将要同步的镜像（不实际执行）

```bash
./sync-images-to-registry.sh --dry-run
```

### 验证镜像是否同步成功

```bash
# 验证 yurt-iot-dock
skopeo list-tags docker://quanzhenglong.com/openyurt/yurt-iot-dock

# 验证 EdgeX 组件
skopeo list-tags docker://quanzhenglong.com/edgexfoundry/core-command
skopeo list-tags docker://quanzhenglong.com/edgexfoundry/core-metadata
skopeo list-tags docker://quanzhenglong.com/edgexfoundry/device-virtual
skopeo list-tags docker://quanzhenglong.com/edgexfoundry/consul
skopeo list-tags docker://quanzhenglong.com/edgexfoundry/redis
```

## PlatformAdmin 配置示例

同步镜像后，使用以下配置部署 EdgeX：

```yaml
apiVersion: iot.openyurt.io/v1beta1
kind: PlatformAdmin
metadata:
  name: edgex-sample
  namespace: default
spec:
  version: minnesota
  platform: edgex
  imageRegistry: quanzhenglong.com  # ⚠️ 注意：不要加 /edge 或 /openyurt
  nodepools:
    - edge-nodepool
  components:
    - name: yurt-iot-dock
    - name: edgex-device-virtual
    - name: edgex-device-rest
```

## 镜像路径说明

### yurt-iot-dock 路径结构

```
quanzhenglong.com/
└── openyurt/
    └── yurt-iot-dock:latest
```

**原因**: OpenYurt PlatformAdmin 控制器硬编码了 `openyurt/yurt-iot-dock` 路径，会在 `imageRegistry` 前面添加这个路径。

### EdgeX 组件路径结构

```
quanzhenglong.com/
└── edgexfoundry/
    ├── core-command:3.0.0
    ├── core-metadata:3.0.0
    ├── core-data:3.0.0
    ├── device-virtual:3.0.0
    ├── device-rest:3.0.0
    ├── consul:1.16
    └── redis:7.0-alpine
```

**原因**: EdgeX 组件镜像路径定义在 OpenYurt 的 `config-nosecty.json` 中，格式为 `edgexfoundry/<component>:<version>`。

## 镜像大小参考

| 镜像 | 大小（约） |
|------|-----------|
| yurt-iot-dock | ~100 MB |
| core-command | ~20 MB |
| core-metadata | ~20 MB |
| device-virtual | ~15 MB |
| device-rest | ~15 MB |
| consul | ~150 MB |
| redis | ~30 MB |
| **总计** | **~500 MB** |

## 常见问题

### Q: 为什么 yurt-iot-dock 路径是 openyurt 而不是 edge？

A: OpenYurt PlatformAdmin 控制器的代码中硬编码了 `openyurt/yurt-iot-dock` 镜像路径。详见 `/pkg/yurtmanager/controller/platformadmin/iotdock.go:72`。

### Q: 能否只同步部分镜像？

A: 可以。编辑 `sync-images-to-registry.sh` 脚本，注释掉不需要的镜像同步代码。

### Q: 如何验证镜像同步成功？

A: 使用 `skopeo list-tags` 或者 `docker pull` 测试：

```bash
# 方法 1: skopeo
skopeo list-tags docker://quanzhenglong.com/openyurt/yurt-iot-dock

# 方法 2: docker pull
docker pull quanzhenglong.com/openyurt/yurt-iot-dock:latest
```

### Q: 同步失败怎么办？

A: 检查以下几点：
1. 网络连接是否正常
2. 镜像仓库认证信息是否正确
3. 源镜像是否存在（Docker Hub 可能有限速）
4. 查看具体错误信息，针对性解决

## 版本兼容性

| 组件 | 版本 | 兼容性说明 |
|------|------|-----------|
| EdgeX Foundry | Minnesota (3.0.0) | 当前支持版本 |
| OpenYurt | v1.6.0+ | 需要修复版 yurt-iot-dock |
| Kubernetes | v1.23+ | 推荐 v1.23.17 |

## 参考资料

- [EdgeX Foundry Minnesota Release Notes](https://docs.edgexfoundry.org/3.0/)
- [OpenYurt PlatformAdmin API](https://github.com/openyurtio/openyurt/blob/master/pkg/apis/iot/v1beta1/platformadmin_types.go)
- [skopeo 文档](https://github.com/containers/skopeo)

---

**最后更新**: 2025-10-17
**EdgeX 版本**: Minnesota (3.0.0)
**维护者**: Edge Platform Team
