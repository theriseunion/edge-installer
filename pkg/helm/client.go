package helm

import (
	"context"
	"fmt"
	"os"
	"time"

	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/cli"
	"helm.sh/helm/v3/pkg/release"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
)

// Client wraps Helm client operations
type Client struct {
	config   *rest.Config
	settings *cli.EnvSettings
}

// NewClient creates a new Helm client
func NewClient(config *rest.Config) *Client {
	settings := cli.New()
	return &Client{
		config:   config,
		settings: settings,
	}
}

// InstallOptions defines options for Helm installation
type InstallOptions struct {
	// ChartPath is the path to the Helm chart (directory or tgz)
	ChartPath string

	// ReleaseName is the name of the Helm release
	ReleaseName string

	// Namespace is the target namespace
	Namespace string

	// Values are the Helm values to use
	Values map[string]interface{}

	// CreateNamespace indicates whether to create the namespace if it doesn't exist
	CreateNamespace bool

	// Wait indicates whether to wait for resources to be ready
	Wait bool

	// Timeout is the time to wait for operations
	Timeout time.Duration
}

// Install installs a Helm chart
func (c *Client) Install(ctx context.Context, opts InstallOptions) (*release.Release, error) {
	klog.Infof("Installing Helm chart: %s as release: %s in namespace: %s", opts.ChartPath, opts.ReleaseName, opts.Namespace)

	// Create action configuration
	actionConfig, err := c.newActionConfig(opts.Namespace)
	if err != nil {
		return nil, fmt.Errorf("failed to create action config: %w", err)
	}

	// Create install action
	install := action.NewInstall(actionConfig)
	install.ReleaseName = opts.ReleaseName
	install.Namespace = opts.Namespace
	install.CreateNamespace = opts.CreateNamespace
	install.Wait = opts.Wait
	install.Timeout = opts.Timeout

	// Load chart
	chart, err := loader.Load(opts.ChartPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load chart from %s: %w", opts.ChartPath, err)
	}

	// Install chart
	rel, err := install.RunWithContext(ctx, chart, opts.Values)
	if err != nil {
		return nil, fmt.Errorf("failed to install chart: %w", err)
	}

	klog.Infof("Helm chart %s installed successfully as release %s", opts.ChartPath, opts.ReleaseName)
	return rel, nil
}

// UpgradeOptions defines options for Helm upgrade
type UpgradeOptions struct {
	// ChartPath is the path to the Helm chart
	ChartPath string

	// ReleaseName is the name of the Helm release
	ReleaseName string

	// Namespace is the target namespace
	Namespace string

	// Values are the Helm values to use
	Values map[string]interface{}

	// Install indicates whether to install if release doesn't exist
	Install bool

	// Wait indicates whether to wait for resources to be ready
	Wait bool

	// Timeout is the time to wait for operations
	Timeout time.Duration
}

// Upgrade upgrades a Helm release
func (c *Client) Upgrade(ctx context.Context, opts UpgradeOptions) (*release.Release, error) {
	klog.Infof("Upgrading Helm release: %s in namespace: %s", opts.ReleaseName, opts.Namespace)

	// Create action configuration
	actionConfig, err := c.newActionConfig(opts.Namespace)
	if err != nil {
		return nil, fmt.Errorf("failed to create action config: %w", err)
	}

	// Create upgrade action
	upgrade := action.NewUpgrade(actionConfig)
	upgrade.Namespace = opts.Namespace
	upgrade.Install = opts.Install
	upgrade.Wait = opts.Wait
	upgrade.Timeout = opts.Timeout

	// Load chart
	chart, err := loader.Load(opts.ChartPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load chart from %s: %w", opts.ChartPath, err)
	}

	// Upgrade release
	rel, err := upgrade.RunWithContext(ctx, opts.ReleaseName, chart, opts.Values)
	if err != nil {
		return nil, fmt.Errorf("failed to upgrade release: %w", err)
	}

	klog.Infof("Helm release %s upgraded successfully", opts.ReleaseName)
	return rel, nil
}

// Uninstall uninstalls a Helm release
func (c *Client) Uninstall(ctx context.Context, releaseName, namespace string) error {
	klog.Infof("Uninstalling Helm release: %s from namespace: %s", releaseName, namespace)

	// Create action configuration
	actionConfig, err := c.newActionConfig(namespace)
	if err != nil {
		return fmt.Errorf("failed to create action config: %w", err)
	}

	// Create uninstall action
	uninstall := action.NewUninstall(actionConfig)

	// Uninstall release
	_, err = uninstall.Run(releaseName)
	if err != nil {
		return fmt.Errorf("failed to uninstall release: %w", err)
	}

	klog.Infof("Helm release %s uninstalled successfully", releaseName)
	return nil
}

// GetRelease gets information about a Helm release
func (c *Client) GetRelease(releaseName, namespace string) (*release.Release, error) {
	// Create action configuration
	actionConfig, err := c.newActionConfig(namespace)
	if err != nil {
		return nil, fmt.Errorf("failed to create action config: %w", err)
	}

	// Create get action
	get := action.NewGet(actionConfig)

	// Get release
	rel, err := get.Run(releaseName)
	if err != nil {
		return nil, fmt.Errorf("failed to get release: %w", err)
	}

	return rel, nil
}

// ListReleases lists all Helm releases in a namespace
func (c *Client) ListReleases(namespace string) ([]*release.Release, error) {
	// Create action configuration
	actionConfig, err := c.newActionConfig(namespace)
	if err != nil {
		return nil, fmt.Errorf("failed to create action config: %w", err)
	}

	// Create list action
	list := action.NewList(actionConfig)
	list.All = true

	// List releases
	releases, err := list.Run()
	if err != nil {
		return nil, fmt.Errorf("failed to list releases: %w", err)
	}

	return releases, nil
}

// ReleaseExists checks if a Helm release exists
func (c *Client) ReleaseExists(releaseName, namespace string) (bool, error) {
	_, err := c.GetRelease(releaseName, namespace)
	if err != nil {
		if err.Error() == fmt.Sprintf("release: not found") {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// newActionConfig creates a new Helm action configuration
func (c *Client) newActionConfig(namespace string) (*action.Configuration, error) {
	actionConfig := new(action.Configuration)

	// Initialize action configuration
	// Use in-cluster config or kubeconfig from environment
	if err := actionConfig.Init(c.settings.RESTClientGetter(), namespace, os.Getenv("HELM_DRIVER"), klog.Infof); err != nil {
		return nil, err
	}

	return actionConfig, nil
}
