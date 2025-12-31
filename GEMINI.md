# Edge Installer - Gemini Context

## Project Overview

`edge-installer` is a unified installation and management framework for an Edge Computing Platform based on Kubernetes. It uses a declarative architecture where a **Component Controller** manages the lifecycle of edge components (like OpenYurt, KubeEdge, Monitoring, Console) defined as custom resources (`Component` CRs).

### Core Architecture

1.  **Unified Entrypoint**: The `edge-controller` Helm chart is the single entry point for installation.
2.  **Self-Contained Artifacts**: All component Helm charts are packaged into a `ChartMuseum` image (`edge-museum`), allowing the platform to be installed in air-gapped environments without external dependencies.
3.  **Declarative Management**:
    *   Users/Admins define `Component` CRs (Custom Resources).
    *   The `edge-controller` reconciles these CRs.
    *   It fetches the corresponding Helm chart from the local `chartmuseum` service.
    *   It executes the Helm install/upgrade via the Helm SDK.

### Key Subsystems

*   **Edge Core**: `edge-apiserver`, `edge-controller`, `edge-console`.
*   **Edge Infrastructure**: Supports **OpenYurt** (`yurthub`, `yurt-manager`) and **KubeEdge**.
*   **Virtualization**: Includes `vcluster` for tenant isolation.
*   **VAST Platform**: A specialized subsystem for AI/Device management (visible in `vast/` and `Makefile` targets).

## Key Directories & Files

| Path | Description |
| :--- | :--- |
| **`edge-controller/`** | **Master Helm Chart**. Bootstraps the system, installs CRDs, and deploys the Controller and ChartMuseum. |
| `edge-apiserver/` | Helm chart for the aggregated API server (permissions/RBAC). |
| `edge-console/` | Helm chart for the Web UI. |
| `edge-monitoring/` | Helm chart for the Prometheus/Grafana stack. |
| `vast/` | Helm chart and configuration for the VAST (Device/AI) platform. |
| `scripts/` | Utility scripts for installation, cleanup, and image synchronization. |
| `bin/_output/` | Destination for packaged `.tgz` Helm charts. |
| `Makefile` | Central control for building, packaging, and deploying. |
| `Dockerfile.museum` | Definition for the image that bundles all Helm charts. |

## Development & Usage

### 1. Prerequisites
*   Kubernetes Cluster
*   Helm v3+
*   `kubectl`

### 2. Building & Packaging
The `Makefile` is the primary interface for build tasks.

*   **Package all charts**:
    ```bash
    make package-charts
    ```
    *Creates `.tgz` files in `bin/_output/`.*

*   **Build & Push ChartMuseum Image** (Required if modifying charts):
    ```bash
    make docker-build-museum MUSEUM_IMG=my-registry/edge-museum:tag
    make docker-push-museum MUSEUM_IMG=my-registry/edge-museum:tag
    ```

### 3. Installation

**Standard Installation (All Components):**
```bash
helm install edge-platform ./edge-controller \
  --namespace edge-system \
  --create-namespace
```

**Mode-Based Installation:**
*   **Host Cluster** (Control Plane + Console):
    ```bash
    helm install edge-platform ./edge-controller \
      --namespace edge-system \
      --create-namespace \
      --set global.mode=host
    ```
*   **Member Cluster** (Worker only, no Console):
    ```bash
    helm install edge-platform ./edge-controller \
      --namespace edge-system \
      --create-namespace \
      --set global.mode=member
    ```

**VAST Platform Installation:**
```bash
make apply-vast-crds
make install-vast
```

### 4. Troubleshooting

*   **Component Stuck in Terminating**:
    The controller manages finalizers. If the controller is deleted *before* components, CRs may get stuck.
    *   *Fix*: Delete CRs first, or manually remove finalizers if the controller is already gone.
    ```bash
    kubectl patch component <name> -n edge-system -p '{"metadata":{"finalizers":[]}}' --type=merge
    ```

*   **Chart 404 Errors**:
    Check the `chartmuseum` pod logs. Ensure the `version` in the Component CR matches a packaged chart in the museum image.

*   **Uninstall**:
    ```bash
    helm uninstall edge-platform -n edge-system
    kubectl delete namespace edge-system
    ```
    *Note: CRDs usually remain and must be deleted manually if a full clean is required.*

## Conventions

*   **CRD-Driven**: All major logic is driven by Custom Resource Definitions (`crds/` directories).
*   **Helm-First**: Deployment logic should primarily live in Helm templates, not ad-hoc scripts.
*   **Namespace Isolation**: Core components live in `edge-system` or `observability-system`. VAST lives in `rise-vast-system`.
