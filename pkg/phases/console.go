package phases

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
	"github.com/theriseunion/installer/pkg/helm"
)

const (
	consoleChartPath   = "/charts/edge-console"
	consoleReleaseName = "edge-console"
	consoleNamespace   = "edge-system"
)

// ConsoleInstaller handles edge-console installation
type ConsoleInstaller struct {
	helmClient *helm.Client
	k8sClient  client.Client
}

// NewConsoleInstaller creates a new console installer
func NewConsoleInstaller(helmClient *helm.Client, k8sClient client.Client) *ConsoleInstaller {
	return &ConsoleInstaller{
		helmClient: helmClient,
		k8sClient:  k8sClient,
	}
}

// Install installs the edge-console component
func (i *ConsoleInstaller) Install(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Installing edge-console...")

	spec := installation.Spec.Components.Console

	// Build Helm values
	values := i.buildValues(installation, spec)

	// Check if release already exists
	exists, err := i.helmClient.ReleaseExists(consoleReleaseName, consoleNamespace)
	if err != nil {
		return fmt.Errorf("failed to check if release exists: %w", err)
	}

	if exists {
		klog.Infof("Release %s already exists, upgrading...", consoleReleaseName)
		_, err = i.helmClient.Upgrade(ctx, helm.UpgradeOptions{
			ChartPath:   consoleChartPath,
			ReleaseName: consoleReleaseName,
			Namespace:   consoleNamespace,
			Values:      values,
			Wait:        true,
			Timeout:     5 * time.Minute,
		})
		if err != nil {
			return fmt.Errorf("failed to upgrade console: %w", err)
		}
	} else {
		klog.Infof("Installing release %s...", consoleReleaseName)
		_, err = i.helmClient.Install(ctx, helm.InstallOptions{
			ChartPath:       consoleChartPath,
			ReleaseName:     consoleReleaseName,
			Namespace:       consoleNamespace,
			Values:          values,
			CreateNamespace: true,
			Wait:            true,
			Timeout:         5 * time.Minute,
		})
		if err != nil {
			return fmt.Errorf("failed to install console: %w", err)
		}
	}

	// Update component status
	installation.Status.Components.Console = installerv1alpha1.ComponentStatus{
		Installed:   true,
		Version:     installation.Spec.Version,
		HelmRelease: consoleReleaseName,
		Ready:       true,
	}

	klog.Info("edge-console installed successfully")
	return nil
}

// buildValues builds Helm values from installation spec
func (i *ConsoleInstaller) buildValues(installation *installerv1alpha1.Installation, spec installerv1alpha1.ConsoleSpec) map[string]interface{} {
	values := make(map[string]interface{})

	// Set replicas
	if spec.Replicas != nil {
		values["replicaCount"] = *spec.Replicas
	}

	// Set image configuration
	if spec.Image.Repository != "" {
		if values["image"] == nil {
			values["image"] = make(map[string]interface{})
		}
		imageMap := values["image"].(map[string]interface{})
		imageMap["repository"] = spec.Image.Repository

		if spec.Image.Tag != "" {
			imageMap["tag"] = spec.Image.Tag
		}

		if spec.Image.PullPolicy != "" {
			imageMap["pullPolicy"] = string(spec.Image.PullPolicy)
		}
	}

	// Set resources
	if spec.Resources.Limits != nil || spec.Resources.Requests != nil {
		values["resources"] = spec.Resources
	}

	// Configure Ingress if enabled
	if spec.Ingress.Enabled {
		ingress := make(map[string]interface{})
		ingress["enabled"] = true

		if spec.Ingress.Host != "" {
			ingress["hosts"] = []map[string]interface{}{
				{
					"host": spec.Ingress.Host,
					"paths": []map[string]interface{}{
						{
							"path":     "/",
							"pathType": "Prefix",
						},
					},
				},
			}
		}

		if spec.Ingress.TLS {
			ingress["tls"] = []map[string]interface{}{
				{
					"secretName": fmt.Sprintf("%s-tls", consoleReleaseName),
					"hosts":      []string{spec.Ingress.Host},
				},
			}
		}

		values["ingress"] = ingress
	}

	// Merge additional values from spec
	if spec.Values != nil && spec.Values.Raw != nil {
		var additionalValues map[string]interface{}
		if err := json.Unmarshal(spec.Values.Raw, &additionalValues); err == nil {
			for k, v := range additionalValues {
				values[k] = v
			}
		}
	}

	return values
}
