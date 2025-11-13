OpenYurt 中 Calico 通过 YurtHub 访问云端的机制

  一、核心架构设计

  1. YurtHub 作为本地代理

  YurtHub 的角色定位：
  - YurtHub 是 OpenYurt 的核心组件，作为边缘节点上的本地 Kubernetes API 代理
  - 部署方式：以 Static Pod 形式运行在每个边缘节点的 kube-system 命名空间
  - 监听地址：
    - 127.0.0.1:10261 - kubelet 连接端口
    - 169.254.2.1:10268 - CNI 插件（包括 Calico）连接端口
    - 127.0.0.1:10267 - 健康检查端口

  2. 数据流向

  边缘节点上的请求流:

  Calico CNI Plugin
      ↓ (访问 https://169.254.2.1:10268)
  YurtHub (本地代理)
      ↓ (TLS 认证 + 缓存)
  云端 Kubernetes API Server
      ↓ (返回 ClusterInformation, IPPool 等资源)
  YurtHub (缓存响应)
      ↓
  Calico CNI Plugin

  二、关键配置机制

  1. YurtHub 的 TLS 证书配置（最关键）

  --hub-cert-organizations=system:nodes 参数：

  这是 Calico 能够通过 YurtHub 访问云端的核心配置：

  # /etc/kubernetes/manifests/yurthub.yaml
  containers:
  - command:
    - yurthub
    - --v=2
    - --bind-address=127.0.0.1
    - --server-addr=https://192.168.1.102:6443  # 云端 API Server
    - --node-name=$(NODE_NAME)
    - --bootstrap-file=/var/lib/yurthub/bootstrap-hub.conf
    - --working-mode=edge
    - --namespace=kube-system
    - --hub-cert-organizations=system:nodes  # ← 关键配置

  为什么这个参数如此重要？

  1. TLS 证书组织名：这个参数让 YurtHub 生成的 TLS 证书包含 O=system:nodes 组织字段
  2. Kubernetes RBAC 授权：Kubernetes 的 RBAC 系统识别 system:nodes 组，赋予节点级别的权限
  3. Calico 认证需求：Calico CNI plugin 使用 ServiceAccount token 访问 API 时，需要 YurtHub 的证书被 Kubernetes 信任

  验证证书：
  # 在边缘节点上
  curl -k -v https://169.254.2.1:10268/apis 2>&1 | grep subject
  # 应该显示：subject: O=system:nodes; CN=system:node:NODE_NAME

  2. Calico 的 CNI 配置

  Calico 如何知道通过 YurtHub 访问？

  在边缘节点上，Calico 的 install-cni 初始化容器会创建 /etc/cni/net.d/calico-kubeconfig 文件：

  # /etc/cni/net.d/calico-kubeconfig
  apiVersion: v1
  kind: Config
  clusters:
  - cluster:
      certificate-authority-data: <base64-encoded-ca-cert>
      server: https://169.254.2.1:10268  # ← 指向 YurtHub
    name: kubernetes
  contexts:
  - context:
      cluster: kubernetes
      user: calico
    name: calico-context
  current-context: calico-context
  users:
  - name: calico
    user:
      token: eyJhbGc...  # calico ServiceAccount 的 token

  关键点：
  - server: https://169.254.2.1:10268 - Calico 所有 API 请求都发往 YurtHub
  - token - 使用 Calico ServiceAccount 的 token 进行身份验证

  3. Kubelet 配置

  kubelet 同样通过 YurtHub 访问云端：

  # /etc/kubernetes/kubelet.conf (由 yurtadm join 自动配置)
  clusters:
  - cluster:
      certificate-authority-data: ...
      server: https://127.0.0.1:10261  # ← kubelet 通过 10261 端口
    name: kubernetes

  三、完整的工作流程

  场景：Calico 创建 Pod 网络时访问 ClusterInformation

  1. CNI 插件执行：
  # kubelet 创建 Pod 时调用 Calico CNI plugin
  /opt/cni/bin/calico
  2. 读取配置：
    - CNI plugin 读取 /etc/cni/net.d/calico-kubeconfig
    - 获取 API Server 地址：https://169.254.2.1:10268
    - 获取认证 token（calico ServiceAccount）
  3. 发起 API 请求：
  GET https://169.254.2.1:10268/apis/crd.projectcalico.org/v1/clusterinformations/default
  Authorization: Bearer <calico-sa-token>
  4. YurtHub 处理请求：
    - 接收 CNI 的请求（端口 10268）
    - 验证 TLS 连接（使用 --hub-cert-organizations=system:nodes 生成的证书）
    - 检查本地缓存
        - 命中缓存：直接返回（边缘自治场景）
      - 未命中：转发到云端 API Server
  5. 转发到云端：
  YurtHub → https://192.168.1.102:6443/apis/crd.projectcalico.org/v1/clusterinformations/default
  6. 云端 API Server 响应：
    - 验证 YurtHub 的证书（O=system:nodes 组织）
    - 返回 ClusterInformation 资源
  7. YurtHub 缓存并返回：
    - 将响应缓存到 /var/lib/yurthub/cache/
    - 返回给 Calico CNI plugin
  8. Calico 完成网络配置：
    - 使用获取的 ClusterInformation 配置网络
    - 分配 IP 地址、创建路由等

  四、关键的网络配置要求

  NO_PROXY 配置（避免代理干扰）

  如果边缘节点配置了 HTTP 代理（用于拉取镜像），必须将 YurtHub 的链路本地地址加入 NO_PROXY：

  # /etc/systemd/system/containerd.service.d/http-proxy.conf
  [Service]
  Environment="HTTP_PROXY=http://proxy-server:port"
  Environment="HTTPS_PROXY=http://proxy-server:port"
  Environment="NO_PROXY=localhost,127.0.0.1,169.254.0.0/16,192.168.1.0/24,10.233.0.0/16"
  #                                        ↑
  #                              必须包含 169.254.0.0/16

  为什么？
  - CNI plugin 继承 containerd 的环境变量
  - 如果没有 169.254.0.0/16 在 NO_PROXY 中，CNI 对 169.254.2.1:10268 的请求会被转发到代理服务器
  - 代理服务器无法访问链路本地地址 → TLS handshake timeout

  五、边缘自治能力

  YurtHub 的缓存机制：

  1. 正常场景（云边连通）：
    - YurtHub 转发请求到云端
    - 缓存响应到本地磁盘
  2. 离线场景（云边断连）：
    - YurtHub 检测到云端不可达
    - 直接从缓存返回数据给 Calico
    - Calico 继续正常工作（边缘自治）
  3. 缓存路径：
  /var/lib/yurthub/cache/

  六、故障排查关键点

  根据文档中的实际案例，常见问题包括：

  问题 1：TLS Handshake Timeout

  症状：
  Get "https://169.254.2.1:10268/apis/crd.projectcalico.org/v1/clusterinformations/default":
  net/http: TLS handshake timeout

  可能原因：
  1. ❌ YurtHub 未配置 --hub-cert-organizations=system:nodes
  2. ❌ containerd 代理配置未排除 169.254.0.0/16
  3. ❌ YurtHub 未正常启动

  排查步骤：
  # 1. 检查 YurtHub 证书
  curl -k -v https://169.254.2.1:10268/apis 2>&1 | grep subject

  # 2. 检查 NO_PROXY 配置
  cat /etc/systemd/system/containerd.service.d/http-proxy.conf

  # 3. 检查 YurtHub 运行状态
  crictl ps | grep yurt-hub
  curl http://127.0.0.1:10267/v1/healthz

  问题 2：Pod 停留在 ContainerCreating

  根因：CNI 插件无法通过 YurtHub 获取 Calico 资源

  解决：确保 YurtHub 配置中包含 --hub-cert-organizations=system:nodes

  七、总结

  Calico 通过 YurtHub 访问云端的机制设定：

  1. 配置层面：
    - YurtHub 必须配置 --hub-cert-organizations=system:nodes
    - Calico 的 kubeconfig 指向 https://169.254.2.1:10268
    - NO_PROXY 必须包含 169.254.0.0/16
  2. 认证层面：
    - YurtHub 使用 system:nodes 组织的 TLS 证书
    - Calico 使用 ServiceAccount token 认证
    - Kubernetes RBAC 授权 system:nodes 组访问 API
  3. 数据流层面：
  Calico CNI → 169.254.2.1:10268 (YurtHub) → 云端 API Server → 响应 → YurtHub 缓存 → Calico
  4. 边缘自治：
    - 云边连通时：YurtHub 转发 + 缓存
    - 云边断连时：YurtHub 从缓存返回
    - Calico 无感知切换，保持正常工作

  核心要点：--hub-cert-organizations=system:nodes 是 Calico 通过 YurtHub 访问云端的关键配置，缺少此配置会导致 TLS 握手失败，Pod 无法创建网络。