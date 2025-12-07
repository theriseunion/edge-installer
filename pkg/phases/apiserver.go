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
	apiserverChartPath   = "/charts/edge-apiserver"
	apiserverReleaseName = "edge-apiserver"
	apiserverNamespace   = "edge-system"
)

// APIServerInstaller handles edge-apiserver installation
type APIServerInstaller struct {
	helmClient *helm.Client
	k8sClient  client.Client
}

// NewAPIServerInstaller creates a new API server installer
func NewAPIServerInstaller(helmClient *helm.Client, k8sClient client.Client) *APIServerInstaller {
	return &APIServerInstaller{
		helmClient: helmClient,
		k8sClient:  k8sClient,
	}
}

// Install installs the edge-apiserver component
func (i *APIServerInstaller) Install(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Installing edge-apiserver...")

	spec := installation.Spec.Components.APIServer

	// Build Helm values
	values := i.buildValues(installation, spec)

	// Check if release already exists
	exists, err := i.helmClient.ReleaseExists(apiserverReleaseName, apiserverNamespace)
	if err != nil {
		return fmt.Errorf("failed to check if release exists: %w", err)
	}

	if exists {
		klog.Infof("Release %s already exists, upgrading...", apiserverReleaseName)
		_, err = i.helmClient.Upgrade(ctx, helm.UpgradeOptions{
			ChartPath:   apiserverChartPath,
			ReleaseName: apiserverReleaseName,
			Namespace:   apiserverNamespace,
			Values:      values,
			Wait:        true,
			Timeout:     5 * time.Minute,
		})
		if err != nil {
			return fmt.Errorf("failed to upgrade apiserver: %w", err)
		}
	} else {
		klog.Infof("Installing release %s...", apiserverReleaseName)
		_, err = i.helmClient.Install(ctx, helm.InstallOptions{
			ChartPath:       apiserverChartPath,
			ReleaseName:     apiserverReleaseName,
			Namespace:       apiserverNamespace,
			Values:          values,
			CreateNamespace: true,
			Wait:            true,
			Timeout:         5 * time.Minute,
		})
		if err != nil {
			return fmt.Errorf("failed to install apiserver: %w", err)
		}
	}

	// Update component status
	installation.Status.Components.APIServer = installerv1alpha1.ComponentStatus{
		Installed:   true,
		Version:     installation.Spec.Version,
		HelmRelease: apiserverReleaseName,
		Ready:       true,
	}

	klog.Info("edge-apiserver installed successfully")
	return nil
}

// buildValues builds Helm values from installation spec
func (i *APIServerInstaller) buildValues(installation *installerv1alpha1.Installation, spec installerv1alpha1.APIServerSpec) map[string]interface{} {
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
