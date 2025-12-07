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
	controllerChartPath  = "/charts/edge-controller"
	controllerReleaseName = "edge-controller"
	controllerNamespace  = "edge-system"
)

// ControllerInstaller handles edge-controller installation
type ControllerInstaller struct {
	helmClient *helm.Client
	k8sClient  client.Client
}

// NewControllerInstaller creates a new controller installer
func NewControllerInstaller(helmClient *helm.Client, k8sClient client.Client) *ControllerInstaller {
	return &ControllerInstaller{
		helmClient: helmClient,
		k8sClient:  k8sClient,
	}
}

// Install installs the edge-controller component
func (i *ControllerInstaller) Install(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Installing edge-controller...")

	spec := installation.Spec.Components.Controller

	// Build Helm values
	values := i.buildValues(installation, spec)

	// Check if release already exists
	exists, err := i.helmClient.ReleaseExists(controllerReleaseName, controllerNamespace)
	if err != nil {
		return fmt.Errorf("failed to check if release exists: %w", err)
	}

	if exists {
		klog.Infof("Release %s already exists, upgrading...", controllerReleaseName)
		_, err = i.helmClient.Upgrade(ctx, helm.UpgradeOptions{
			ChartPath:   controllerChartPath,
			ReleaseName: controllerReleaseName,
			Namespace:   controllerNamespace,
			Values:      values,
			Wait:        true,
			Timeout:     5 * time.Minute,
		})
		if err != nil {
			return fmt.Errorf("failed to upgrade controller: %w", err)
		}
	} else {
		klog.Infof("Installing release %s...", controllerReleaseName)
		_, err = i.helmClient.Install(ctx, helm.InstallOptions{
			ChartPath:       controllerChartPath,
			ReleaseName:     controllerReleaseName,
			Namespace:       controllerNamespace,
			Values:          values,
			CreateNamespace: true,
			Wait:            true,
			Timeout:         5 * time.Minute,
		})
		if err != nil {
			return fmt.Errorf("failed to install controller: %w", err)
		}
	}

	// Update component status
	installation.Status.Components.Controller = installerv1alpha1.ComponentStatus{
		Installed:   true,
		Version:     installation.Spec.Version,
		HelmRelease: controllerReleaseName,
		Ready:       true,
	}

	klog.Info("edge-controller installed successfully")
	return nil
}

// buildValues builds Helm values from installation spec
func (i *ControllerInstaller) buildValues(installation *installerv1alpha1.Installation, spec installerv1alpha1.ControllerSpec) map[string]interface{} {
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

	// Enable initialization if configured
	if spec.EnableInit {
		values["enableInit"] = true

		// Pass initialization config
		if installation.Spec.Initialization.Enabled {
			initConfig := make(map[string]interface{})

			if installation.Spec.Initialization.ClusterName != "" {
				initConfig["clusterName"] = installation.Spec.Initialization.ClusterName
			}

			if installation.Spec.Initialization.SystemWorkspace != "" {
				initConfig["systemWorkspace"] = installation.Spec.Initialization.SystemWorkspace
			}

			if len(installation.Spec.Initialization.SystemNamespaces) > 0 {
				initConfig["systemNamespaces"] = installation.Spec.Initialization.SystemNamespaces
			}

			values["initialization"] = initConfig
		}
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
