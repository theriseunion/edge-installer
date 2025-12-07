package main

import (
	"context"
	"flag"
	"fmt"

	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/klog/v2"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
	"github.com/theriseunion/installer/pkg/installer"
)

var (
	kubeconfig      string
	masterURL       string
	installationName string
	namespace       string
	mode            string
)

func main() {
	klog.InitFlags(nil)

	flag.StringVar(&kubeconfig, "kubeconfig", "", "Path to kubeconfig file")
	flag.StringVar(&masterURL, "master", "", "Kubernetes master URL")
	flag.StringVar(&mode, "mode", "operator", "Running mode: operator, install, uninstall")
	flag.StringVar(&installationName, "installation", "edge-platform", "Installation CR name (for install/uninstall mode)")
	flag.StringVar(&namespace, "namespace", "edge-system", "Installation namespace")

	flag.Parse()

	klog.Info("Starting Edge Installer...")
	klog.Infof("Mode: %s", mode)

	// Build K8s configuration
	cfg, err := buildConfig(kubeconfig, masterURL)
	if err != nil {
		klog.Fatalf("Failed to build kubeconfig: %v", err)
	}

	// Create Scheme
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		klog.Fatalf("Failed to add client-go scheme: %v", err)
	}
	if err := installerv1alpha1.AddToScheme(scheme); err != nil {
		klog.Fatalf("Failed to add installer v1alpha1 to scheme: %v", err)
	}

	// Create client
	k8sClient, err := client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		klog.Fatalf("Failed to create Kubernetes client: %v", err)
	}

	ctx := ctrl.SetupSignalHandler()

	switch mode {
	case "operator":
		if err := runOperator(ctx, cfg, scheme); err != nil {
			klog.Fatalf("Failed to run operator: %v", err)
		}
	case "install":
		if err := runInstall(ctx, k8sClient); err != nil {
			klog.Fatalf("Failed to run installation: %v", err)
		}
	case "uninstall":
		if err := runUninstall(ctx, k8sClient); err != nil {
			klog.Fatalf("Failed to run uninstallation: %v", err)
		}
	default:
		klog.Fatalf("Unknown mode: %s (must be operator, install, or uninstall)", mode)
	}
}

func buildConfig(kubeconfig, masterURL string) (*rest.Config, error) {
	if kubeconfig != "" {
		return clientcmd.BuildConfigFromFlags(masterURL, kubeconfig)
	}
	return rest.InClusterConfig()
}

func runOperator(ctx context.Context, cfg *rest.Config, scheme *runtime.Scheme) error {
	klog.Info("Running in operator mode...")

	// Create controller manager
	mgr, err := ctrl.NewManager(cfg, ctrl.Options{
		Scheme: scheme,
	})
	if err != nil {
		return fmt.Errorf("failed to create controller manager: %w", err)
	}

	// Register Installation controller
	if err = (&installer.InstallationReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
		Config: cfg,
	}).SetupWithManager(mgr); err != nil {
		return fmt.Errorf("failed to setup Installation controller: %w", err)
	}

	klog.Info("Starting controller manager...")
	return mgr.Start(ctx)
}

func runInstall(ctx context.Context, k8sClient client.Client) error {
	klog.Infof("Running in install mode for Installation: %s/%s", namespace, installationName)

	// Create installation orchestrator
	orchestrator := installer.NewOrchestrator(k8sClient, nil)

	// Get Installation CR
	installation := &installerv1alpha1.Installation{}
	if err := k8sClient.Get(ctx, client.ObjectKey{
		Name:      installationName,
		Namespace: namespace,
	}, installation); err != nil {
		return fmt.Errorf("failed to get Installation CR: %w", err)
	}

	// Run installation
	klog.Info("Starting installation...")
	if err := orchestrator.Run(ctx, installation); err != nil {
		return fmt.Errorf("installation failed: %w", err)
	}

	klog.Info("Installation completed successfully!")
	return nil
}

func runUninstall(ctx context.Context, k8sClient client.Client) error {
	klog.Infof("Running in uninstall mode for Installation: %s/%s", namespace, installationName)

	// TODO: Implement uninstallation logic
	klog.Warning("Uninstall mode is not yet implemented")

	return nil
}
