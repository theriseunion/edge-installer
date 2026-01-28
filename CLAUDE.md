# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Edge Platform Installer** - a Kubernetes-based edge computing platform deployment tool. It uses a unified Helm + ChartMuseum + Component Custom Resource architecture to provide declarative, single-command installation of all edge platform components.

## Architecture

### Core Design Pattern

```
User declares desired state (Component CRs)
         ↓
Component Controller automatically reconciles
         ↓
Fetches charts from built-in ChartMuseum
         ↓
Helm installs/upgrades components
```

### Key Components

1. **edge-controller** - Parent Helm chart (unified entry point)
   - Contains Component CRD definitions
   - Deploys ChartMuseum (with pre-packaged charts as sub-chart)
   - Deploys Component Controller operator
   - Creates Component CRs based on installation mode

2. **ChartMuseum** - Built-in Helm chart repository
   - Embedded in Docker image (`Dockerfile.museum`)
   - Pre-loaded with all component charts
   - No external chart repository dependencies

3. **Component Controller** - Kubernetes operator
   - Watches Component CRs
   - Reconciles by installing charts via Helm SDK
   - Skips components annotated with `skip-reconcile: true`

4. **Component Charts** - Individual component Helm charts
   - edge-apiserver, edge-console, edge-monitoring, edge-duty, edge-ota, kubeedge, vcluster, yurt-manager, yurthub, vast, traefik, bin-downloader, iot-apiserver, iot-controller, vcluster-k8s-addition, yurt-iot-dock

### Installation Modes

The `global.mode` value in `edge-controller/values.yaml` controls which components get installed:

| Mode | Controller | APIServer | Console | Monitoring | VAST | Traefik | Bin Downloader | OTA |
|------|------------|-----------|---------|------------|------|---------|----------------|-----|
| **all** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **host** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **member** | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **none** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

## Common Development Commands

### Building and Packaging

```bash
# Package all Helm charts (clean first, then package)
make package-charts

# Build ChartMuseum Docker image with packaged charts
make docker-build-museum MUSEUM_IMG=quanzhenglong.com/edge/edge-museum:your-tag

# Push ChartMuseum image
make docker-push-museum MUSEUM_IMG=quanzhenglong.com/edge/edge-museum:your-tag

# Cross-platform build and push (amd64, arm64)
make docker-buildx-museum MUSEUM_IMG=quanzhenglong.com/edge/edge-museum:your-tag
```

### Local Testing

```bash
# Dry-run installation to verify templates
helm install test ./edge-controller --dry-run --debug

# Lint Helm chart
make lint
# OR
helm lint ./edge-controller

# Show rendered templates
make template
# OR
helm template edge-platform ./edge-controller

# Check packaged chart contents
tar -tzf bin/_output/edge-apiserver-0.1.0.tgz | head
```

### Installation

```bash
# Quick install all components (standalone cluster)
helm install edge-platform ./edge-controller --namespace edge-system --create-namespace

# Host cluster (with console)
helm install edge-platform ./edge-controller --namespace edge-system --create-namespace --set global.mode=host

# Member cluster (without console)
helm install edge-platform ./edge-controller --namespace edge-system --create-namespace --set global.mode=member

# Custom registry and tag
helm install edge-platform ./edge-controller \
  --namespace edge-system --create-namespace \
  --set global.imageRegistry=your-registry.com/edge \
  --set global.imageTag=v1.0.0

# Allow scheduling on any node (default: control-plane only)
helm install edge-platform ./edge-controller \
  --namespace edge-system --create-namespace \
  --set 'nodeSelector={}'
```

### Verification

```bash
# Check component status
kubectl get pods -n edge-system
kubectl get components -A

# Check Helm releases
helm list -n edge-system
helm get all edge-apiserver -n edge-system

# Access console
kubectl port-forward svc/edge-console 3000:3000 -n edge-system
# Visit http://localhost:3000
```

### Uninstallation

**IMPORTANT**: Delete Component CRs first to avoid stuck resources with finalizers

```bash
# 1. Delete Component CRs (let running controller process finalizers)
kubectl delete component --all -n edge-system
kubectl delete component --all -n observability-system
kubectl delete component --all -n rise-vast-system

# 2. Wait for Component CRs to be fully deleted
kubectl wait --for=delete component --all -n edge-system --timeout=120s

# 3. Uninstall Helm release
helm uninstall edge-platform -n edge-system

# 4. Delete namespaces (optional)
kubectl delete namespace edge-system observability-system rise-vast-system

# 5. Delete CRDs (optional, removes all custom resources)
kubectl delete crd -l app.kubernetes.io/part-of=edge-platform
```

## CRD Management

When modifying CRDs (e.g., from edge-apiserver):

```bash
# 1. Generate CRDs in source project
cd edge-apiserver
make manifests

# 2. Copy to edge-controller
cp config/crd/bases/*.yaml ../edge-installer/edge-controller/crds/

# 3. Rebuild ChartMuseum image (includes updated CRDs)
cd ../edge-installer
make package-charts
make docker-buildx-museum MUSEUM_IMG=quanzhenglong.com/edge/edge-museum:your-tag

# 4. Restart chartmuseum to load new charts
kubectl rollout restart deployment/chartmuseum -n edge-system
```

## Adding New Components

When adding a new component to the platform:

1. **Create the Helm chart**:
   ```bash
   mkdir my-component
   helm create my-component
   ```

2. **Update Makefile CHARTS list** (Makefile:27):
   ```makefile
   CHARTS := edge-apiserver edge-console ... my-component
   ```

3. **Create Component CR template** (`edge-controller/templates/components/my-component.yaml`):
   ```yaml
   {{- if .Values.autoInstall.myComponent.enabled }}
   apiVersion: ext.theriseunion.io/v1alpha1
   kind: Component
   metadata:
     name: my-component
     namespace: {{ .Release.Namespace }}
     labels:
       app.kubernetes.io/part-of: edge-platform
   spec:
     enabled: {{ .Values.autoInstall.myComponent.enabled }}
     version: {{ .Values.autoInstall.myComponent.version }}
     chart:
       name: my-component
       repository: http://chartmuseum.{{ .Release.Namespace }}.svc:8080
   {{- end }}
   ```

4. **Add configuration to** `edge-controller/values.yaml`:
   ```yaml
   autoInstall:
     myComponent:
       enabled: true
       version: "0.1.0"
       values:
         # Component-specific values
   ```

5. **Rebuild and push ChartMuseum image**:
   ```bash
   make package-charts
   make docker-buildx-museum MUSEUM_IMG=quanzhenglong.com/edge/edge-museum:your-tag
   ```

## Important Architecture Details

### Controller Self-Skip Mechanism

The `edge-controller` Component CR (templates/components/controller.yaml:16) is annotated with `ext.theriseunion.io/skip-reconcile: "true"` to prevent the controller from attempting to install itself via Helm. This prevents a circular dependency since the controller is already deployed directly by the parent Helm chart.

### Helm Dependency Ordering

The `edge-controller/Chart.yaml` defines `chartmuseum` as a dependency, ensuring it's deployed before the controller. This guarantees the ChartMuseum service is available when the controller starts reconciling Component CRs.

### Component CR Version Field

Every Component CR must specify a `version` field. Without it, the controller constructs an invalid chart URL (e.g., `edge-monitoring-.tgz`), resulting in 404 errors.

### Namespace Auto-Binding

System namespaces (`edge-system`, `observability-system`, `rise-vast-system`) are automatically bound to the `system-workspace` via controller initialization logic with labels `theriseunion.io/workspace: system-workspace` and `theriseunion.io/managed: "true"`.

### Namespace Usage

The platform uses multiple namespaces for isolation:
- **edge-system** - Core platform components (controller, apiserver, console, traefik)
- **observability-system** - Monitoring stack (Prometheus, Grafana, AlertManager)
- **rise-vast-system** - VAST GPU/NPU management (HAMI, VAST controller)
- **cert-manager** - Certificate management (VAST dependency)
- **ota-system** - Edge OTA update service

### Node Scheduling

By default, core components (controller, apiserver, console) use `nodeSelector.node-role.kubernetes.io/control-plane: ""` to schedule on control-plane nodes. For Kubernetes < 1.20, use `node-role.kubernetes.io/master: ""`. To schedule on any node, set `nodeSelector: {}`.

### VAST Platform Special Handling

VAST requires special CRD management before upgrades:
```bash
make apply-vast-crds
```

This waits for VAST CRDs to be established before proceeding with upgrades, avoiding validation errors.

## Troubleshooting

### Component CR Stuck in Terminating

**Cause**: Finalizer cannot be processed (controller was deleted before Component CRs)

**Solution**: Always delete Component CRs before uninstalling Helm. Never manually remove finalizers (leaves orphaned resources).

### Chart URL 404 Errors

**Cause**: Component CR missing `version` field

**Solution**: Ensure all Component CRs have `spec.version` set

### CRD Validation Errors

**Cause**: ChartMuseum image contains outdated CRDs

**Solution**: Update source CRDs, rebuild ChartMuseum image, restart chartmuseum deployment

### ChartMuseum Connection Issues

```bash
# Check service
kubectl get svc chartmuseum -n edge-system

# Check pod
kubectl get pods -n edge-system -l app.kubernetes.io/name=chartmuseum

# Check logs
kubectl logs -n edge-system -l app.kubernetes.io/name=chartmuseum

# Test connection
kubectl run test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k http://chartmuseum.edge-system.svc:8080/health
```

### VAST/HAMI Device Plugin Issues

#### Ascend Device Plugin Not Starting

**Symptoms**: Ascend device plugin pods failing to start or crash looping

**Common causes**:
1. Node not labeled with `ascend=on`
2. Ascend driver not installed at `/usr/local/Ascend/driver`
3. Incorrect `ascend310P` setting (`pro` vs `standard`)

**Solution**:
```bash
# Check node labels
kubectl get nodes -L ascend

# Label node if needed
kubectl label node <node-name> ascend=on

# Check device plugin logs
kubectl logs -n rise-vast-system -l app.kubernetes.io/component=hami-device-plugin-ascend

# Check if driver exists on node
kubectl debug -n rise-vast-system <ascend-plugin-pod> --image=ubuntu -- \
  ls -la /usr/local/Ascend/driver
```

#### Exporter Not Reporting Metrics

**Symptoms**: Prometheus not scraping Ascend/NVIDIA metrics

**Solution**:
```bash
# Check ServiceMonitor is enabled
kubectl get servicemonitor -n rise-vast-system

# Verify Service has correct annotations
kubectl get svc -n rise-vast-system -o yaml | grep -A 5 prometheus.io/scrape

# Check exporter pod logs
kubectl logs -n rise-vast-system -l app.kubernetes.io/component=hami-exporter-ascend

# Test metrics endpoint directly
kubectl port-forward -n rise-vast-system <exporter-pod> 8082:8082
curl http://localhost:8082/metrics
```

#### Webhook Configuration Blocking Pod Creation

**Symptoms**: Pods stuck in creation, webhook timeout errors

**Solution**:
```bash
# Check webhook configurations
kubectl get validatingwebhookconfiguration -A | grep vast
kubectl get mutatingwebhookconfiguration -A | grep vast

# Temporarily disable webhook for testing
kubectl patch validatingwebhookconfiguration <name> --type='json' \
  -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value":"Ignore"}]'

# Check webhook service is reachable
kubectl get svc -n rise-vast-system
kubectl ep -n rise-vast-system
```

## File Structure Reference

```
edge-installer/
├── edge-controller/           # Parent Helm chart (entry point)
│   ├── Chart.yaml             # Defines chartmuseum dependency
│   ├── values.yaml            # Global configuration (modes, autoInstall settings)
│   ├── crds/                  # All CRD definitions
│   ├── charts/
│   │   └── chartmuseum/       # ChartMuseum sub-chart
│   └── templates/
│       ├── controller/        # Controller deployment
│       ├── components/        # Component CR templates
│       └── rbac/              # RBAC resources
├── vast/                      # VAST GPU/NPU management platform
│   ├── Chart.yaml             # VAST parent chart
│   ├── values.yaml            # VAST global config (accelerators, HAMI settings)
│   └── charts/
│       ├── cert-manager/      # Certificate management subchart
│       ├── apiserver/         # VAST API server (device CRDs)
│       ├── controller/        # VAST controller operator
│       └── hami/              # HAMI device plugin and scheduler
│           ├── templates/
│           │   ├── device-plugin/  # Per-accelerator plugins (nvidia, ascend, etc.)
│           │   ├── exporter/       # Metrics exporters
│           │   └── scheduler/      # Custom scheduler
│           └── values.yaml         # HAMI device configuration
├── [component-charts]/        # Individual component Helm charts
│   ├── edge-apiserver/        # Edge API server
│   ├── edge-console/          # Edge web console
│   ├── edge-monitoring/       # Prometheus monitoring stack
│   ├── edge-duty/             # Duty management
│   ├── edge-ota/              # OTA update service
│   ├── kubeedge/              # KubeEdge edge computing
│   ├── vcluster/              # Virtual clusters
│   ├── vcluster-k8s-addition/ # vCluster additions
│   ├── yurt-manager/          # OpenYurt manager
│   ├── yurthub/               # OpenYurt hub
│   ├── yurt-iot-dock/         # OpenYurt IoT dock
│   ├── traefik/               # Traefik ingress
│   ├── bin-downloader/        # Binary downloader
│   ├── iot-apiserver/         # IoT API server
│   └── iot-controller/        # IoT controller
├── Dockerfile.museum          # ChartMuseum image build
├── Makefile                   # Build automation
├── deploy.sh                  # Interactive deployment script
└── README.md                  # Comprehensive documentation
```

## VAST Platform

VAST is a GPU/NPU accelerator management platform that uses HAMI (formerly ham-vgpu) for device virtualization and scheduling.

### Supported Hardware Accelerators

VAST/HAMI supports multiple hardware types:
- **NVIDIA** (nvidia.com/gpu) - NVIDIA GPUs
- **Ascend** (huawei.com/Ascend*) - Huawei NPU chips (Ascend910A/B2/B3/B4, Ascend310P)
- **Hygon** (hygon.com/dcu) - Hygon DCU
- **Cambricon** (cambricon.com/vmlu) - Cambricon MLU
- **Kunlunxin** (kunlunxin.com/xpu) - Kunlunxin XPU
- **Iluvatar** (iluvatar.ai/vgpu) - Iluvatar GPU
- **Metax** (metax-tech.com/sgpu) - Metax SGPU
- **Enflame** (enflame.com/gcu) - Enflame GCU
- **Alibaba** (alibabacloud.com/ppu) - Alibaba PPU

### VAST Deployment

```bash
# Install VAST with cert-manager dependency
make install-vast

# Uninstall VAST (includes cert-manager cleanup)
make uninstall-vast

# Apply VAST CRDs manually (required before upgrades)
make apply-vast-crds
```

### VAST Architecture

```
vast/ (parent Helm chart)
├── cert-manager/     # Certificate management subchart
├── apiserver/        # VAST API server (device.theriseunion.io CRDs)
├── controller/       # VAST controller operator
└── hami/             # HAMI device plugin and scheduler
    ├── device-plugin/  # Device plugins for each accelerator type
    ├── exporter/       # Metrics exporters (NVIDIA DCGM, Ascend NPU exporter, etc.)
    └── scheduler/      # Custom scheduler for accelerator-aware scheduling
```

### Enabling Accelerator Support

To enable specific accelerator support in VAST, configure `vast/values.yaml`:

```yaml
hami:
  devices:
    nvidia:
      gpuCorePolicy: default
    ascend:
      enabled: true
      image: "quanzhenglong.com/camp/ascend-device-plugin:v2.4.4-08"
      nodeSelector:
        ascend: "on"
      ascend310P: "pro"  # or "standard"
  exporter:
    ascend:
      enabled: true
      image: "quanzhenglong.com/camp/npu-exporter:v1.0.1"
      service:
        httpPort: 38082
```

Node labeling is required for device scheduling:
```bash
# Label nodes with accelerator type
kubectl label node <node-name> ascend=on
kubectl label node <node-name> gpu=on
```

### VAST Resource Types

VAST introduces several CRDs for device management:
- **DeviceModel** (`device.theriseunion.io/v1alpha1`) - Device templates for GPU/NPU types
- **NodeConfig** (`device.theriseunion.io/v1alpha1`) - Per-node device configuration
- **ComputeTemplate** (`device.theriseunion.io/v1alpha1`) - Compute instance templates
- **ResourcePool** (`device.theriseunion.io/v1alpha1`) - Device pool management
- **ResourcePoolItem** (`device.theriseunion.io/v1alpha1`) - Individual pool items
- **GlobalConfig** (`device.theriseunion.io/v1alpha1`) - Global VAST settings

### VAST Device Models

VAST uses `DeviceModel` CRs to define device templates. Pre-configured models exist in `vast/charts/controller/templates/`:
- `devicemodel-nvidia-v100.yaml`
- `devicemodel-nvidia-a100.yaml`
- `devicemodel-nvidia-a30.yaml`
- `devicemodel-ascend-310p.yaml`

## Registry Configuration

Default registry: `quanzhenglong.com/edge`

Override via:
- `global.imageRegistry` in values.yaml
- `--set global.imageRegistry=...` during helm install
- `REGISTRY` make variable for ChartMuseum builds

## Edge OTA Service

The Edge OTA (Over-The-Air) update service provides firmware and software update capabilities for edge devices.

```bash
# Install OTA service with bundled NATS
make install-ota

# Install OTA without NATS (use external NATS)
make install-ota-no-nats

# Uninstall OTA service
make uninstall-ota

# Uninstall OTA CRDs (WARNING: deletes all OTA resources)
make uninstall-ota-crds
```

OTA creates an `APIService` for `v1alpha1.ota.theriseunion.io` and manages:
- **OTANodes** - Edge node registration and status
- **Tasks** - Individual update tasks
- **Playbooks** - Update orchestration playbooks

## Additional Makefile Targets

Beyond the basic build commands, additional targets are available:

```bash
# VAST Management
make install-vast              # Install VAST platform
make uninstall-vast            # Uninstall VAST (clean)
make apply-vast-crds           # Apply VAST CRDs

# Cert Manager (standalone)
make install-cert-manager      # Install cert-manager only
make uninstall-cert-manager    # Uninstall cert-manager only

# OTA Management
make install-ota               # Install Edge OTA service
make install-ota-no-nats       # Install OTA without NATS
make uninstall-ota             # Uninstall OTA service
make uninstall-ota-crds        # Delete OTA CRDs

# Quick Installation
make install-all               # Install all components (mode=all)
make install-host              # Install host cluster components
make install-member            # Install member cluster components
make install-controller-only   # Install only controller infrastructure
make upgrade-all               # Upgrade all components
```

## Edge Computing Frameworks

The platform supports multiple edge computing frameworks for different use cases:

### KubeEdge

KubeEdge is a Kubernetes-native edge computing framework that extends Kubernetes to edge nodes.

**Key Components**:
- **CloudCore** - Cloud-side component (runs in edge-system namespace)
- **EdgeCore** - Edge-side component (runs on edge nodes)

**Architecture**: Edge nodes connect to cloud hub via WebSocket, maintaining a lightweight control plane.

### OpenYurt

OpenYurt is an open-source edge computing framework based on Kubernetes.

**Key Components**:
- **Yurt-manager** - Manages edge node lifecycle
- **YurtHub** - Autonomous edge node agent
- **Yurt-IoT-Dock** - IoT device integration

**Architecture**: Uses a "cloud-edge" architecture with edge autonomy support.

### vCluster

vCluster creates virtual Kubernetes clusters within a single physical cluster.

**Use Case**: Multi-tenancy and isolated environments for different teams or workloads.

**Key Features**:
- Each vCluster has its own API server and control plane
- Shares underlying worker nodes
- Provides complete isolation at the control plane level

### Framework Selection

| Framework | Best For | Isolation | Complexity |
|-----------|----------|-----------|------------|
| **KubeEdge** | Distributed edge locations | Network isolation | Medium |
| **OpenYurt** | Edge autonomy and IoT | Network + compute | Medium |
| **vCluster** | Multi-tenant clusters | Control plane isolation | Low |

All three can coexist in the same platform, configured via `edge-controller/values.yaml`.
