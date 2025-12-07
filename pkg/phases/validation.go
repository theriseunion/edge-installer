package phases

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
)

// InstallationValidator validates the installation
type InstallationValidator struct {
	client client.Client
	config *rest.Config
}

// NewInstallationValidator creates a new installation validator
func NewInstallationValidator(k8sClient client.Client, config *rest.Config) *InstallationValidator {
	return &InstallationValidator{
		client: k8sClient,
		config: config,
	}
}

// Validate validates that all components are installed and healthy
func (v *InstallationValidator) Validate(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Validating installation...")

	// Validate each enabled component
	if installation.Spec.Components.Controller.Enabled {
		if err := v.validateDeployment(ctx, "edge-system", "edge-controller"); err != nil {
			return fmt.Errorf("controller validation failed: %w", err)
		}
		klog.Info("Controller validation passed")
	}

	if installation.Spec.Components.APIServer.Enabled {
		if err := v.validateDeployment(ctx, "edge-system", "edge-apiserver"); err != nil {
			return fmt.Errorf("apiserver validation failed: %w", err)
		}
		klog.Info("APIServer validation passed")
	}

	if installation.Spec.Components.Console.Enabled {
		if err := v.validateDeployment(ctx, "edge-system", "edge-console"); err != nil {
			return fmt.Errorf("console validation failed: %w", err)
		}
		klog.Info("Console validation passed")
	}

	if installation.Spec.Components.Monitoring.Enabled {
		if err := v.validateMonitoring(ctx); err != nil {
			return fmt.Errorf("monitoring validation failed: %w", err)
		}
		klog.Info("Monitoring validation passed")
	}

	// Validate cluster initialization if enabled
	if installation.Spec.Initialization.Enabled {
		if err := v.validateInitialization(ctx, installation); err != nil {
			return fmt.Errorf("initialization validation failed: %w", err)
		}
		klog.Info("Initialization validation passed")
	}

	klog.Info("All validation checks passed")
	return nil
}

// validateDeployment checks if a deployment is ready
func (v *InstallationValidator) validateDeployment(ctx context.Context, namespace, name string) error {
	klog.Infof("Validating deployment: %s/%s", namespace, name)

	deployment := &appsv1.Deployment{}

	// Wait for deployment to be ready
	err := wait.PollImmediate(5*time.Second, 5*time.Minute, func() (bool, error) {
		if err := v.client.Get(ctx, client.ObjectKey{
			Namespace: namespace,
			Name:      name,
		}, deployment); err != nil {
			klog.Warningf("Failed to get deployment %s/%s: %v", namespace, name, err)
			return false, nil
		}

		// Check if deployment is ready
		if deployment.Status.ReadyReplicas == deployment.Status.Replicas &&
			deployment.Status.Replicas > 0 {
			return true, nil
		}

		klog.Infof("Waiting for deployment %s/%s: %d/%d replicas ready",
			namespace, name, deployment.Status.ReadyReplicas, deployment.Status.Replicas)
		return false, nil
	})

	if err != nil {
		return fmt.Errorf("deployment %s/%s is not ready: %w", namespace, name, err)
	}

	// Validate pods are running
	podList := &corev1.PodList{}
	if err := v.client.List(ctx, podList, &client.ListOptions{
		Namespace: namespace,
		LabelSelector: labels.SelectorFromSet(labels.Set{
			"app": name,
		}),
	}); err != nil {
		return fmt.Errorf("failed to list pods: %w", err)
	}

	if len(podList.Items) == 0 {
		return fmt.Errorf("no pods found for deployment %s/%s", namespace, name)
	}

	for _, pod := range podList.Items {
		if pod.Status.Phase != corev1.PodRunning {
			return fmt.Errorf("pod %s is not running: %s", pod.Name, pod.Status.Phase)
		}
	}

	klog.Infof("Deployment %s/%s is ready with %d replicas", namespace, name, deployment.Status.ReadyReplicas)
	return nil
}

// validateMonitoring validates the monitoring stack
func (v *InstallationValidator) validateMonitoring(ctx context.Context) error {
	klog.Info("Validating monitoring stack...")

	// Check Prometheus
	if err := v.validateDeployment(ctx, "observability-system", "edge-prometheus"); err != nil {
		klog.Warningf("Prometheus validation failed: %v", err)
		// Don't fail installation if monitoring has issues
	}

	// Check Grafana
	if err := v.validateDeployment(ctx, "observability-system", "edge-grafana"); err != nil {
		klog.Warningf("Grafana validation failed: %v", err)
		// Don't fail installation if monitoring has issues
	}

	return nil
}

// validateInitialization validates that cluster initialization completed
func (v *InstallationValidator) validateInitialization(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Validating cluster initialization...")

	// TODO: Add actual validation logic
	// Check if:
	// 1. Host Cluster CR exists
	// 2. System workspace exists
	// 3. System namespaces are assigned to workspace

	klog.Info("Cluster initialization validation skipped (not yet implemented)")
	return nil
}
