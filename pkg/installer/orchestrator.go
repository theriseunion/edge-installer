package installer

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
	"github.com/theriseunion/installer/pkg/helm"
	"github.com/theriseunion/installer/pkg/phases"
)

// Orchestrator manages the installation workflow
type Orchestrator struct {
	client     client.Client
	config     *rest.Config
	helmClient *helm.Client
}

// NewOrchestrator creates a new installation orchestrator
func NewOrchestrator(k8sClient client.Client, config *rest.Config) *Orchestrator {
	return &Orchestrator{
		client:     k8sClient,
		config:     config,
		helmClient: helm.NewClient(config),
	}
}

// Run executes the complete installation workflow
func (o *Orchestrator) Run(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Infof("Starting installation orchestration for: %s/%s", installation.Namespace, installation.Name)

	// Define installation phases in order
	installationPhases := []struct {
		name      string
		phase     installerv1alpha1.InstallationPhase
		condition installerv1alpha1.ConditionType
		execute   func(context.Context, *installerv1alpha1.Installation) error
	}{
		{
			name:      "Prerequisites Check",
			phase:     installerv1alpha1.PhaseChecking,
			condition: installerv1alpha1.ConditionPrerequisitesChecked,
			execute:   o.executePrerequisitesCheck,
		},
		{
			name:      "CRD Installation",
			phase:     installerv1alpha1.PhaseInstalling,
			condition: installerv1alpha1.ConditionCRDsInstalled,
			execute:   o.executeCRDInstallation,
		},
		{
			name:      "Component Installation",
			phase:     installerv1alpha1.PhaseInstalling,
			condition: installerv1alpha1.ConditionComponentsInstalled,
			execute:   o.executeComponentInstallation,
		},
		{
			name:      "Cluster Initialization",
			phase:     installerv1alpha1.PhaseInitializing,
			condition: installerv1alpha1.ConditionInitializationComplete,
			execute:   o.executeInitialization,
		},
		{
			name:      "Installation Validation",
			phase:     installerv1alpha1.PhaseValidating,
			condition: installerv1alpha1.ConditionReady,
			execute:   o.executeValidation,
		},
	}

	// Execute each phase
	for _, p := range installationPhases {
		klog.Infof("Executing phase: %s", p.name)

		// Update installation phase
		if err := o.updatePhase(ctx, installation, p.phase, p.name); err != nil {
			return fmt.Errorf("failed to update phase to %s: %w", p.phase, err)
		}

		// Execute phase
		if err := p.execute(ctx, installation); err != nil {
			o.setCondition(installation, p.condition, "False", "ExecutionFailed", err.Error())
			return fmt.Errorf("phase %s failed: %w", p.name, err)
		}

		// Set success condition
		o.setCondition(installation, p.condition, "True", "ExecutionSucceeded", fmt.Sprintf("%s completed successfully", p.name))

		klog.Infof("Phase %s completed successfully", p.name)
	}

	return nil
}

// executePrerequisitesCheck validates that the cluster meets installation requirements
func (o *Orchestrator) executePrerequisitesCheck(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Checking installation prerequisites...")

	validator := phases.NewPrerequisitesValidator(o.client, o.config)
	if err := validator.Validate(ctx); err != nil {
		return fmt.Errorf("prerequisites check failed: %w", err)
	}

	klog.Info("Prerequisites check passed")
	return nil
}

// executeCRDInstallation installs all required CRDs
func (o *Orchestrator) executeCRDInstallation(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Installing CRDs...")

	installer := phases.NewCRDInstaller(o.client, o.config)
	if err := installer.Install(ctx, installation); err != nil {
		return fmt.Errorf("CRD installation failed: %w", err)
	}

	klog.Info("CRDs installed successfully")
	return nil
}

// executeComponentInstallation installs all enabled components
func (o *Orchestrator) executeComponentInstallation(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Installing components...")

	// Install Controller (must be first)
	if installation.Spec.Components.Controller.Enabled {
		klog.Info("Installing edge-controller...")
		installer := phases.NewControllerInstaller(o.helmClient, o.client)
		if err := installer.Install(ctx, installation); err != nil {
			return fmt.Errorf("controller installation failed: %w", err)
		}
		klog.Info("edge-controller installed successfully")
	}

	// Install API Server
	if installation.Spec.Components.APIServer.Enabled {
		klog.Info("Installing edge-apiserver...")
		installer := phases.NewAPIServerInstaller(o.helmClient, o.client)
		if err := installer.Install(ctx, installation); err != nil {
			return fmt.Errorf("apiserver installation failed: %w", err)
		}
		klog.Info("edge-apiserver installed successfully")
	}

	// Install Console
	if installation.Spec.Components.Console.Enabled {
		klog.Info("Installing edge-console...")
		installer := phases.NewConsoleInstaller(o.helmClient, o.client)
		if err := installer.Install(ctx, installation); err != nil {
			return fmt.Errorf("console installation failed: %w", err)
		}
		klog.Info("edge-console installed successfully")
	}

	// Install Monitoring (optional)
	if installation.Spec.Components.Monitoring.Enabled {
		klog.Info("Installing monitoring stack...")
		installer := phases.NewMonitoringInstaller(o.helmClient, o.client)
		if err := installer.Install(ctx, installation); err != nil {
			return fmt.Errorf("monitoring installation failed: %w", err)
		}
		klog.Info("Monitoring stack installed successfully")
	}

	klog.Info("All components installed successfully")
	return nil
}

// executeInitialization performs cluster initialization
func (o *Orchestrator) executeInitialization(ctx context.Context, installation *installerv1alpha1.Installation) error {
	// Skip if initialization is disabled
	if !installation.Spec.Initialization.Enabled {
		klog.Info("Cluster initialization is disabled, skipping")
		return nil
	}

	klog.Info("Initializing cluster...")

	initializer := phases.NewClusterInitializer(o.client, o.config, installation.Spec.Initialization)
	if err := initializer.Initialize(ctx); err != nil {
		return fmt.Errorf("cluster initialization failed: %w", err)
	}

	klog.Info("Cluster initialized successfully")
	return nil
}

// executeValidation validates the installation
func (o *Orchestrator) executeValidation(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Validating installation...")

	validator := phases.NewInstallationValidator(o.client, o.config)
	if err := validator.Validate(ctx, installation); err != nil {
		return fmt.Errorf("installation validation failed: %w", err)
	}

	klog.Info("Installation validated successfully")
	return nil
}

// updatePhase updates the installation phase and status message
func (o *Orchestrator) updatePhase(ctx context.Context, installation *installerv1alpha1.Installation, phase installerv1alpha1.InstallationPhase, message string) error {
	// Fetch latest version to avoid conflicts
	key := client.ObjectKeyFromObject(installation)
	latest := &installerv1alpha1.Installation{}
	if err := o.client.Get(ctx, key, latest); err != nil {
		if errors.IsNotFound(err) {
			return nil
		}
		return err
	}

	latest.Status.Phase = phase
	latest.Status.CurrentPhase = message

	if err := o.client.Status().Update(ctx, latest); err != nil {
		return fmt.Errorf("failed to update installation status: %w", err)
	}

	// Update local copy
	installation.Status = latest.Status

	return nil
}

// setCondition sets a condition on the Installation status
func (o *Orchestrator) setCondition(installation *installerv1alpha1.Installation, condType installerv1alpha1.ConditionType, status, reason, message string) {
	now := metav1.Now()

	// Find existing condition
	for i, cond := range installation.Status.Conditions {
		if cond.Type == condType {
			// Update existing condition
			installation.Status.Conditions[i].Status = status
			installation.Status.Conditions[i].Reason = reason
			installation.Status.Conditions[i].Message = message
			installation.Status.Conditions[i].LastTransitionTime = now
			return
		}
	}

	// Add new condition
	installation.Status.Conditions = append(installation.Status.Conditions, installerv1alpha1.InstallationCondition{
		Type:               condType,
		Status:             status,
		LastTransitionTime: now,
		Reason:             reason,
		Message:            message,
	})
}
