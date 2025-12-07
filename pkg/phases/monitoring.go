package phases

import (
	"context"
	"fmt"
	"time"

	"k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
	"github.com/theriseunion/installer/pkg/helm"
)

const (
	monitoringChartPath   = "/charts/edge-monitoring"
	monitoringReleaseName = "edge-monitoring"
	monitoringNamespace   = "observability-system"
)

// MonitoringInstaller handles monitoring stack installation
type MonitoringInstaller struct {
	helmClient *helm.Client
	k8sClient  client.Client
}

// NewMonitoringInstaller creates a new monitoring installer
func NewMonitoringInstaller(helmClient *helm.Client, k8sClient client.Client) *MonitoringInstaller {
	return &MonitoringInstaller{
		helmClient: helmClient,
		k8sClient:  k8sClient,
	}
}

// Install installs the monitoring stack (Prometheus + Grafana)
func (i *MonitoringInstaller) Install(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Installing monitoring stack...")

	spec := installation.Spec.Components.Monitoring

	// Build Helm values
	values := i.buildValues(installation, spec)

	// Check if release already exists
	exists, err := i.helmClient.ReleaseExists(monitoringReleaseName, monitoringNamespace)
	if err != nil {
		return fmt.Errorf("failed to check if release exists: %w", err)
	}

	if exists {
		klog.Infof("Release %s already exists, upgrading...", monitoringReleaseName)
		_, err = i.helmClient.Upgrade(ctx, helm.UpgradeOptions{
			ChartPath:   monitoringChartPath,
			ReleaseName: monitoringReleaseName,
			Namespace:   monitoringNamespace,
			Values:      values,
			Wait:        true,
			Timeout:     10 * time.Minute, // Monitoring stack may take longer
		})
		if err != nil {
			return fmt.Errorf("failed to upgrade monitoring: %w", err)
		}
	} else {
		klog.Infof("Installing release %s...", monitoringReleaseName)
		_, err = i.helmClient.Install(ctx, helm.InstallOptions{
			ChartPath:       monitoringChartPath,
			ReleaseName:     monitoringReleaseName,
			Namespace:       monitoringNamespace,
			Values:          values,
			CreateNamespace: true,
			Wait:            true,
			Timeout:         10 * time.Minute,
		})
		if err != nil {
			return fmt.Errorf("failed to install monitoring: %w", err)
		}
	}

	// Update component status
	installation.Status.Components.Monitoring = installerv1alpha1.ComponentStatus{
		Installed:   true,
		Version:     installation.Spec.Version,
		HelmRelease: monitoringReleaseName,
		Ready:       true,
	}

	klog.Info("Monitoring stack installed successfully")
	return nil
}

// buildValues builds Helm values from installation spec
func (i *MonitoringInstaller) buildValues(installation *installerv1alpha1.Installation, spec installerv1alpha1.MonitoringSpec) map[string]interface{} {
	values := make(map[string]interface{})

	// Configure Prometheus
	if spec.Prometheus.Enabled {
		prometheus := make(map[string]interface{})
		prometheus["enabled"] = true

		// Set retention period
		if spec.Prometheus.Retention != "" {
			prometheus["retention"] = spec.Prometheus.Retention
		} else {
			prometheus["retention"] = "15d" // Default retention
		}

		values["prometheus"] = prometheus
	}

	// Configure Grafana
	if spec.Grafana.Enabled {
		grafana := make(map[string]interface{})
		grafana["enabled"] = true

		values["grafana"] = grafana
	}

	return values
}
