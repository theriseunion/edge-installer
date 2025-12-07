package installer

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/event"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
)

const (
	// FinalizerName is the finalizer added to Installation resources
	FinalizerName = "installer.theriseunion.io/finalizer"
)

// InstallationReconciler reconciles an Installation object
type InstallationReconciler struct {
	client.Client
	Scheme *runtime.Scheme
	Config *rest.Config
}

// Reconcile implements the reconciliation loop for Installation resources
// +kubebuilder:rbac:groups=installer.theriseunion.io,resources=installations,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=installer.theriseunion.io,resources=installations/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=installer.theriseunion.io,resources=installations/finalizers,verbs=update
func (r *InstallationReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	klog.Infof("Reconciling Installation: %s/%s", req.Namespace, req.Name)

	// Fetch the Installation instance
	installation := &installerv1alpha1.Installation{}
	if err := r.Get(ctx, req.NamespacedName, installation); err != nil {
		if errors.IsNotFound(err) {
			klog.Infof("Installation resource not found: %s/%s. Ignoring since object must be deleted", req.Namespace, req.Name)
			return ctrl.Result{}, nil
		}
		klog.Errorf("Failed to get Installation: %v", err)
		return ctrl.Result{}, err
	}

	// Handle deletion
	if !installation.DeletionTimestamp.IsZero() {
		return r.handleDeletion(ctx, installation)
	}

	// Add finalizer if not present
	if !controllerutil.ContainsFinalizer(installation, FinalizerName) {
		controllerutil.AddFinalizer(installation, FinalizerName)
		if err := r.Update(ctx, installation); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	// Handle installation based on current phase
	return r.handleInstallation(ctx, installation)
}

// handleInstallation processes the installation workflow
func (r *InstallationReconciler) handleInstallation(ctx context.Context, installation *installerv1alpha1.Installation) (ctrl.Result, error) {
	// Skip if already installed
	if installation.Status.Phase == installerv1alpha1.PhaseInstalled {
		klog.Infof("Installation %s/%s is already complete", installation.Namespace, installation.Name)
		return ctrl.Result{}, nil
	}

	// Skip if failed (manual intervention required)
	if installation.Status.Phase == installerv1alpha1.PhaseFailed {
		klog.Infof("Installation %s/%s is in failed state. Manual intervention required.", installation.Namespace, installation.Name)
		return ctrl.Result{}, nil
	}

	// Initialize status if needed
	if installation.Status.Phase == "" {
		installation.Status.Phase = installerv1alpha1.PhasePending
		installation.Status.CurrentPhase = "Waiting to start installation"
		now := metav1.Now()
		installation.Status.StartTime = &now
		if err := r.Status().Update(ctx, installation); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	// Create orchestrator
	orchestrator := NewOrchestrator(r.Client, r.Config)

	// Run installation
	klog.Infof("Starting installation for %s/%s", installation.Namespace, installation.Name)
	if err := orchestrator.Run(ctx, installation); err != nil {
		klog.Errorf("Installation failed: %v", err)

		// Update status to failed
		installation.Status.Phase = installerv1alpha1.PhaseFailed
		installation.Status.Message = fmt.Sprintf("Installation failed: %v", err)
		if updateErr := r.Status().Update(ctx, installation); updateErr != nil {
			klog.Errorf("Failed to update Installation status: %v", updateErr)
			return ctrl.Result{}, updateErr
		}

		return ctrl.Result{}, err
	}

	// Update status to installed
	installation.Status.Phase = installerv1alpha1.PhaseInstalled
	installation.Status.CurrentPhase = "Installation completed successfully"
	now := metav1.Now()
	installation.Status.CompletionTime = &now

	// Add Ready condition
	r.setCondition(installation, installerv1alpha1.ConditionReady, "True", "InstallationComplete", "All components installed and initialized")

	if err := r.Status().Update(ctx, installation); err != nil {
		return ctrl.Result{}, err
	}

	klog.Infof("Installation %s/%s completed successfully", installation.Namespace, installation.Name)
	return ctrl.Result{}, nil
}

// handleDeletion handles the cleanup when Installation is being deleted
func (r *InstallationReconciler) handleDeletion(ctx context.Context, installation *installerv1alpha1.Installation) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(installation, FinalizerName) {
		return ctrl.Result{}, nil
	}

	klog.Infof("Handling deletion for Installation: %s/%s", installation.Namespace, installation.Name)

	// TODO: Implement cleanup logic
	// - Uninstall Helm releases
	// - Clean up created resources
	// - Remove cluster initialization data (if needed)

	klog.Warning("Uninstallation logic not yet implemented")

	// Remove finalizer
	controllerutil.RemoveFinalizer(installation, FinalizerName)
	if err := r.Update(ctx, installation); err != nil {
		return ctrl.Result{}, err
	}

	klog.Infof("Installation %s/%s finalizer removed", installation.Namespace, installation.Name)
	return ctrl.Result{}, nil
}

// setCondition sets a condition on the Installation status
func (r *InstallationReconciler) setCondition(installation *installerv1alpha1.Installation, condType installerv1alpha1.ConditionType, status, reason, message string) {
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

// SetupWithManager sets up the controller with the Manager
func (r *InstallationReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&installerv1alpha1.Installation{}).
		WithEventFilter(&installationEventFilter{}).
		Complete(r)
}

// installationEventFilter filters events for Installation resources
type installationEventFilter struct{}

func (f *installationEventFilter) Create(e event.TypedCreateEvent[client.Object]) bool {
	return true
}

func (f *installationEventFilter) Delete(e event.TypedDeleteEvent[client.Object]) bool {
	return true
}

func (f *installationEventFilter) Update(e event.TypedUpdateEvent[client.Object]) bool {
	// Only reconcile on spec changes or status subresource updates
	return true
}

func (f *installationEventFilter) Generic(e event.TypedGenericEvent[client.Object]) bool {
	return false
}
