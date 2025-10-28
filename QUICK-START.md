# Edge Platform 快速开始

## 一句话部署

```bash
git clone https://github.com/edge/apiserver.git
cd apiserver/edge-installer
./deploy.sh
```

## 常用场景

### 开发环境（本地测试）
```bash
./deploy.sh
```

### 生产集群部署
```bash
export KUBECONFIG_PATH=~/.kube/prod.config
export TAG=v1.0.0
export PULL_POLICY=IfNotPresent
./deploy.sh
```

### 完整套件（含监控和边缘计算）
```bash
export KUBECONFIG_PATH=~/.kube/cluster.config
export ENABLE_MONITORING=true
export INSTALL_OPENYURT=true
export OPENYURT_API_SERVER=$(kubectl config view --minify | grep server | awk '{print $2}')
./deploy.sh
```

## 访问服务

部署完成后：

```bash
# API Server
kubectl port-forward -n edge-system svc/apiserver 8080:8080

# Web Console
kubectl port-forward -n edge-system svc/console 3000:3000
```

访问：
- 控制台: http://localhost:3000
- API: http://localhost:8080

## 更新组件

```bash
# 更新所有组件（逐个更新）
export COMPONENT=apiserver && ./update.sh
export COMPONENT=controller && ./update.sh
export COMPONENT=console && ./update.sh
```

## 卸载

```bash
./scripts/uninstall.sh --delete-namespace --delete-crd
```

---

**提示**: 更多详细配置请参考 [README.md](./README.md)