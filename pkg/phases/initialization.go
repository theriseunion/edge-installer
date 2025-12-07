package phases

import (
	"context"

	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
)

// ClusterInitializer handles cluster initialization
type ClusterInitializer struct {
	client client.Client
	config *rest.Config
	spec   installerv1alpha1.InitializationSpec
}

// NewClusterInitializer creates a new cluster initializer
func NewClusterInitializer(k8sClient client.Client, config *rest.Config, spec installerv1alpha1.InitializationSpec) *ClusterInitializer {
	return &ClusterInitializer{
		client: k8sClient,
		config: config,
		spec:   spec,
	}
}

// Initialize performs cluster initialization
// This creates the host cluster CR, system workspace, and assigns system namespaces
func (i *ClusterInitializer) Initialize(ctx context.Context) error {
	klog.Info("Initializing cluster...")

	// The actual initialization is handled by edge-controller with --enable-init flag
	// This phase just validates that initialization will be performed

	if i.spec.ClusterName == "" {
		klog.Warning("No cluster name specified, using default 'host'")
	}

	if i.spec.SystemWorkspace == "" {
		klog.Warning("No system workspace name specified, using default 'system-workspace'")
	}

	if len(i.spec.SystemNamespaces) == 0 {
		klog.Info("No system namespaces specified, controller will use defaults")
	} else {
		klog.Infof("Will assign %d system namespaces to system workspace", len(i.spec.SystemNamespaces))
	}

	// NOTE: The actual initialization logic is executed by edge-controller when it starts
	// with the --enable-init flag. The controller's initialization controller will:
	// 1. Create the host Cluster CR
	// 2. Create the system-workspace
	// 3. Assign system namespaces to the workspace
	// 4. Set cluster annotations
	// 5. Mark initialization as complete

	klog.Info("Cluster initialization configuration validated")
	return nil
}
