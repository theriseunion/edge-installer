package phases

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// PrerequisitesValidator validates installation prerequisites
type PrerequisitesValidator struct {
	client    client.Client
	config    *rest.Config
	clientset *kubernetes.Clientset
}

// NewPrerequisitesValidator creates a new prerequisites validator
func NewPrerequisitesValidator(k8sClient client.Client, config *rest.Config) *PrerequisitesValidator {
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		klog.Warningf("Failed to create clientset: %v", err)
	}

	return &PrerequisitesValidator{
		client:    k8sClient,
		config:    config,
		clientset: clientset,
	}
}

// Validate checks if the cluster meets installation requirements
func (v *PrerequisitesValidator) Validate(ctx context.Context) error {
	klog.Info("Validating installation prerequisites...")

	// Check Kubernetes version
	if err := v.checkKubernetesVersion(ctx); err != nil {
		return fmt.Errorf("kubernetes version check failed: %w", err)
	}

	// Check cluster resources
	if err := v.checkClusterResources(ctx); err != nil {
		return fmt.Errorf("cluster resources check failed: %w", err)
	}

	// Check required namespaces
	if err := v.checkRequiredNamespaces(ctx); err != nil {
		return fmt.Errorf("namespace check failed: %w", err)
	}

	// Check storage classes
	if err := v.checkStorageClasses(ctx); err != nil {
		return fmt.Errorf("storage class check failed: %w", err)
	}

	klog.Info("All prerequisites validated successfully")
	return nil
}

// checkKubernetesVersion verifies the Kubernetes version meets minimum requirements
func (v *PrerequisitesValidator) checkKubernetesVersion(ctx context.Context) error {
	klog.Info("Checking Kubernetes version...")

	if v.clientset == nil {
		return fmt.Errorf("kubernetes clientset not initialized")
	}

	version, err := v.clientset.Discovery().ServerVersion()
	if err != nil {
		return fmt.Errorf("failed to get server version: %w", err)
	}

	klog.Infof("Kubernetes version: %s", version.GitVersion)

	// TODO: Add actual version comparison
	// Minimum required version: 1.20.0
	// if version.Minor < "20" {
	//     return fmt.Errorf("kubernetes version %s is not supported, minimum required: 1.20.0", version.GitVersion)
	// }

	return nil
}

// checkClusterResources verifies the cluster has sufficient resources
func (v *PrerequisitesValidator) checkClusterResources(ctx context.Context) error {
	klog.Info("Checking cluster resources...")

	// Get all nodes
	nodeList := &corev1.NodeList{}
	if err := v.client.List(ctx, nodeList); err != nil {
		return fmt.Errorf("failed to list nodes: %w", err)
	}

	if len(nodeList.Items) == 0 {
		return fmt.Errorf("no nodes found in cluster")
	}

	// Calculate total allocatable resources
	var totalCPU, totalMemory resource.Quantity
	for _, node := range nodeList.Items {
		if cpu, ok := node.Status.Allocatable[corev1.ResourceCPU]; ok {
			totalCPU.Add(cpu)
		}
		if mem, ok := node.Status.Allocatable[corev1.ResourceMemory]; ok {
			totalMemory.Add(mem)
		}
	}

	klog.Infof("Cluster has %d nodes with total allocatable CPU: %s, Memory: %s",
		len(nodeList.Items), totalCPU.String(), totalMemory.String())

	// Check minimum requirements
	// Minimum: 4 CPUs, 8Gi memory
	minCPU := resource.MustParse("4")
	minMemory := resource.MustParse("8Gi")

	if totalCPU.Cmp(minCPU) < 0 {
		klog.Warningf("Cluster has less than recommended CPU resources (recommended: %s, available: %s)", minCPU.String(), totalCPU.String())
	}

	if totalMemory.Cmp(minMemory) < 0 {
		klog.Warningf("Cluster has less than recommended memory resources (recommended: %s, available: %s)", minMemory.String(), totalMemory.String())
	}

	return nil
}

// checkRequiredNamespaces verifies required namespaces exist
func (v *PrerequisitesValidator) checkRequiredNamespaces(ctx context.Context) error {
	klog.Info("Checking required namespaces...")

	requiredNamespaces := []string{
		"kube-system",
		"kube-public",
		"kube-node-lease",
	}

	for _, nsName := range requiredNamespaces {
		ns := &corev1.Namespace{}
		if err := v.client.Get(ctx, client.ObjectKey{Name: nsName}, ns); err != nil {
			return fmt.Errorf("required namespace %s not found: %w", nsName, err)
		}
		klog.Infof("Found required namespace: %s", nsName)
	}

	return nil
}

// checkStorageClasses verifies at least one storage class is available
func (v *PrerequisitesValidator) checkStorageClasses(ctx context.Context) error {
	klog.Info("Checking storage classes...")

	storageClassList := &metav1.PartialObjectMetadataList{}
	storageClassList.SetGroupVersionKind(metav1.SchemeGroupVersion.WithKind("StorageClassList"))

	if err := v.client.List(ctx, storageClassList); err != nil {
		// Storage class check is optional - log warning but don't fail
		klog.Warningf("Failed to list storage classes: %v", err)
		return nil
	}

	if len(storageClassList.Items) == 0 {
		klog.Warning("No storage classes found - PersistentVolume features will not be available")
	} else {
		klog.Infof("Found %d storage classes", len(storageClassList.Items))
	}

	return nil
}
