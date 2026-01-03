# Edge OTA Helm Chart

Edge OTA Service - Over-The-Air device management with remote command execution, file transfer, and Ansible playbook orchestration.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+

## Installation

### Quick Install

```bash
# Install with default configuration
helm install edge-ota ./edge-ota -n ota-system --create-namespace

# Or using Makefile
make install-ota
```

### Install with External NATS

If you have an existing NATS server:

```bash
helm install edge-ota ./edge-ota -n ota-system --create-namespace \
  --set nats.enabled=false \
  --set nats.externalUrl=nats://your-nats-server:4222
```

### Install with Custom Image Registry

```bash
helm install edge-ota ./edge-ota -n ota-system --create-namespace \
  --set global.imageRegistry=your-registry.com \
  --set image.repository=your-org/edge-ota-server \
  --set image.tag=v1.0.0
```

## Uninstallation

```bash
# Uninstall the release
helm uninstall edge-ota -n ota-system

# Or using Makefile (includes cleanup)
make uninstall-ota

# Delete CRDs (WARNING: This deletes all OTA resources)
make uninstall-ota-crds
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of OTA server replicas | `1` |
| `image.registry` | Image registry | `ghcr.io` |
| `image.repository` | Image repository | `theriseunion/edge-ota/server` |
| `image.tag` | Image tag | `latest` |
| `nats.enabled` | Deploy NATS subchart | `true` |
| `nats.externalUrl` | External NATS URL (when nats.enabled=false) | `""` |
| `otaServer.logLevel` | Log level | `info` |
| `apiService.enabled` | Enable Kubernetes API aggregation | `true` |

### Full Configuration

See [values.yaml](./values.yaml) for the complete list of configurable parameters.

## Components

### OTA Server

The main component that provides:
- REST API for device management
- Kubernetes API aggregation layer
- Task orchestration and scheduling
- Playbook execution coordination

### NATS (Subchart)

Message broker for device communication:
- Native NATS protocol (port 4222)
- MQTT protocol for devices (port 8883)
- Health monitoring (port 8222)

### CRDs

Custom Resource Definitions installed:
- `OTANode` - Represents an edge device
- `Task` - Represents a task to execute on devices
- `Playbook` - Represents an Ansible playbook definition

## Usage Examples

### Register a Device

```yaml
apiVersion: ota.theriseunion.io/v1alpha1
kind: OTANode
metadata:
  name: edge-device-001
  namespace: default
spec:
  deviceId: "device-001"
  labels:
    location: "factory-1"
    type: "gateway"
```

### Execute a Command

```yaml
apiVersion: ota.theriseunion.io/v1alpha1
kind: Task
metadata:
  name: check-disk-space
  namespace: default
spec:
  type: exec
  targets:
    - edge-device-001
  command: "df -h"
  timeout: 60
```

### Run a Playbook

```yaml
apiVersion: ota.theriseunion.io/v1alpha1
kind: Task
metadata:
  name: install-docker
  namespace: default
spec:
  type: playbook
  targets:
    - edge-device-001
  playbookRef: install-docker
  timeout: 600
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│  ┌─────────────────┐      ┌─────────────────┐          │
│  │   OTA Server    │◄────►│      NATS       │          │
│  │  (API + Ctrl)   │      │  (MQTT Bridge)  │          │
│  └────────┬────────┘      └────────┬────────┘          │
│           │                        │                    │
│           ▼                        │                    │
│  ┌─────────────────┐              │                    │
│  │   Kubernetes    │              │                    │
│  │   API Server    │              │                    │
│  │  (Aggregated)   │              │                    │
│  └─────────────────┘              │                    │
└───────────────────────────────────┼────────────────────┘
                                    │
                        ┌───────────┴───────────┐
                        │      MQTT/TLS         │
                        ▼                       ▼
                  ┌──────────┐           ┌──────────┐
                  │  Agent   │           │  Agent   │
                  │(Device 1)│           │(Device N)│
                  └──────────┘           └──────────┘
```

## ReverseProxy Configuration

To enable OTA API access through the platform's IAM reverse proxy, create a `ReverseProxy` resource:

```bash
kubectl apply -f crds/reverseproxy.yaml
```

**Or manually create the resource:**

```yaml
apiVersion: iam.theriseunion.io/v1alpha1
kind: ReverseProxy
metadata:
  name: ota-server-proxy
  namespace: ota-system
spec:
  directives:
    rewrite:
      # Universal rule: /oapis/ota.theriseunion.io/v1alpha1/* → /apis/ota.theriseunion.io/v1alpha1/*
      - from: ^/oapis/ota\.theriseunion\.io/v1alpha1/(.*)$
        to: /apis/ota.theriseunion.io/v1alpha1/$1
  matcher:
    method: '*'
    path: /oapis/ota.theriseunion.io/v1alpha1/*
  upstream:
    host: ota-server.ota-system.svc.cluster.local
    port: 9443
    scheme: https
    tls:
      insecureSkipVerify: true
```

**Path Rewrite Examples:**

| Request Path | Rewritten To |
|-------------|--------------|
| `/oapis/ota.theriseunion.io/v1alpha1/otanodes` | `/apis/ota.theriseunion.io/v1alpha1/otanodes` |
| `/oapis/ota.theriseunion.io/v1alpha1/namespaces/default/otanodes/node-1` | `/apis/ota.theriseunion.io/v1alpha1/namespaces/default/otanodes/node-1` |
| `/oapis/ota.theriseunion.io/v1alpha1/catalogs` | `/apis/ota.theriseunion.io/v1alpha1/catalogs` |
| `/oapis/ota.theriseunion.io/v1alpha1/tasks/task-1/status` | `/apis/ota.theriseunion.io/v1alpha1/tasks/task-1/status` |

**Benefits of Single Universal Rule:**

- ✅ Handles all resource types (nodes, tasks, playbooks, catalogs)
- ✅ Supports namespace-scoped and cluster-scoped resources
- ✅ Works with subresources (status, exec, install, etc.)
- ✅ No maintenance needed when adding new resources

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n ota-system
```

### View Server Logs

```bash
kubectl logs -n ota-system -l app.kubernetes.io/name=edge-ota
```

### Check NATS Connectivity

```bash
kubectl logs -n ota-system -l app.kubernetes.io/name=nats
```

### Verify API Aggregation

```bash
kubectl get apiservice v1alpha1.ota.theriseunion.io
```
