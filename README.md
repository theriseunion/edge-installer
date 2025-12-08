# Edge Installer

Edge Platform 组件安装工具 - 基于 ChartMuseum + Component CR 架构

## 快速开始

```bash
# 打包 Charts
make package-charts

# 构建 ChartMuseum 镜像
make docker-build-museum

# 部署到集群
./scripts/install-chartmuseum.sh
kubectl apply -f components/host-components.yaml
```

## 目录结构

```
edge-installer/
├── edge-apiserver/       # APIServer Helm Chart
├── edge-controller/      # Controller Helm Chart (含 CRDs)
├── edge-console/         # Console Helm Chart
├── edge-monitoring/      # Monitoring Helm Chart
├── components/           # Component CR 配置
├── manifests/            # ChartMuseum 部署清单
├── scripts/              # 安装脚本
├── bin/_output/          # Chart 打包产物
├── Dockerfile.museum     # ChartMuseum 镜像
└── Makefile              # 构建工具
```

## 文档

详细文档请参考 `docs-installer/`:
- [安装指南](../docs-installer/edge-installer-guide.md)
- [ChartMuseum 架构](../docs-installer/chartmuseum-architecture.md)
- [Component 安装流程](../docs-installer/component-installation-flow.md)
