package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// InstallationPhase represents the phase of installation
type InstallationPhase string

const (
	PhasePending      InstallationPhase = "Pending"
	PhaseChecking     InstallationPhase = "PrerequisitesChecking"
	PhaseInstalling   InstallationPhase = "Installing"
	PhaseInitializing InstallationPhase = "Initializing"
	PhaseValidating   InstallationPhase = "Validating"
	PhaseInstalled    InstallationPhase = "Installed"
	PhaseFailed       InstallationPhase = "Failed"
	PhaseUpgrading    InstallationPhase = "Upgrading"
)

// ConditionType represents the type of condition
type ConditionType string

const (
	ConditionPrerequisitesChecked ConditionType = "PrerequisitesChecked"
	ConditionCRDsInstalled        ConditionType = "CRDsInstalled"
	ConditionComponentsInstalled  ConditionType = "ComponentsInstalled"
	ConditionInitializationComplete ConditionType = "InitializationComplete"
	ConditionReady                ConditionType = "Ready"
)

// ComponentSpec defines the configuration for a component
type ComponentSpec struct {
	// Enabled indicates if the component should be installed
	Enabled bool `json:"enabled"`

	// Replicas is the number of replicas for the component
	// +optional
	Replicas *int32 `json:"replicas,omitempty"`

	// Image configuration
	// +optional
	Image ImageSpec `json:"image,omitempty"`

	// Resources configuration
	// +optional
	Resources corev1.ResourceRequirements `json:"resources,omitempty"`

	// Additional values for Helm chart
	// +optional
	// +kubebuilder:pruning:PreserveUnknownFields
	Values *runtime.RawExtension `json:"values,omitempty"`
}

// ImageSpec defines container image configuration
type ImageSpec struct {
	// Repository is the image repository
	Repository string `json:"repository,omitempty"`

	// Tag is the image tag
	Tag string `json:"tag,omitempty"`

	// PullPolicy is the image pull policy
	PullPolicy corev1.PullPolicy `json:"pullPolicy,omitempty"`
}

// APIServerSpec defines API Server configuration
type APIServerSpec struct {
	ComponentSpec `json:",inline"`
}

// ControllerSpec defines Controller configuration
type ControllerSpec struct {
	ComponentSpec `json:",inline"`

	// EnableInit enables automatic cluster initialization
	// +optional
	EnableInit bool `json:"enableInit,omitempty"`
}

// ConsoleSpec defines Console configuration
type ConsoleSpec struct {
	ComponentSpec `json:",inline"`

	// Ingress configuration
	// +optional
	Ingress IngressSpec `json:"ingress,omitempty"`
}

// IngressSpec defines Ingress configuration
type IngressSpec struct {
	// Enabled indicates if Ingress should be created
	Enabled bool `json:"enabled"`

	// Host is the Ingress hostname
	// +optional
	Host string `json:"host,omitempty"`

	// TLS configuration
	// +optional
	TLS bool `json:"tls,omitempty"`
}

// MonitoringSpec defines Monitoring configuration
type MonitoringSpec struct {
	// Enabled indicates if monitoring should be installed
	Enabled bool `json:"enabled"`

	// Prometheus configuration
	// +optional
	Prometheus PrometheusSpec `json:"prometheus,omitempty"`

	// Grafana configuration
	// +optional
	Grafana GrafanaSpec `json:"grafana,omitempty"`
}

// PrometheusSpec defines Prometheus configuration
type PrometheusSpec struct {
	// Enabled indicates if Prometheus should be installed
	Enabled bool `json:"enabled"`

	// Retention period
	// +optional
	Retention string `json:"retention,omitempty"`
}

// GrafanaSpec defines Grafana configuration
type GrafanaSpec struct {
	// Enabled indicates if Grafana should be installed
	Enabled bool `json:"enabled"`
}

// ComponentsSpec defines all components configuration
type ComponentsSpec struct {
	// APIServer configuration
	// +optional
	APIServer APIServerSpec `json:"apiserver,omitempty"`

	// Controller configuration
	// +optional
	Controller ControllerSpec `json:"controller,omitempty"`

	// Console configuration
	// +optional
	Console ConsoleSpec `json:"console,omitempty"`

	// Monitoring configuration
	// +optional
	Monitoring MonitoringSpec `json:"monitoring,omitempty"`
}

// InitializationSpec defines cluster initialization configuration
type InitializationSpec struct {
	// Enabled indicates if cluster initialization should be performed
	Enabled bool `json:"enabled"`

	// ClusterName is the name of the host cluster
	// +optional
	ClusterName string `json:"clusterName,omitempty"`

	// SystemWorkspace is the name of the system workspace
	// +optional
	SystemWorkspace string `json:"systemWorkspace,omitempty"`

	// SystemNamespaces are the namespaces to assign to system workspace
	// +optional
	SystemNamespaces []string `json:"systemNamespaces,omitempty"`
}

// InstallationSpec defines the desired state of Installation
type InstallationSpec struct {
	// Version is the version of Edge Platform to install
	Version string `json:"version"`

	// Components configuration
	Components ComponentsSpec `json:"components"`

	// Initialization configuration
	// +optional
	Initialization InitializationSpec `json:"initialization,omitempty"`
}

// InstallationCondition describes the state of an installation at a certain point
type InstallationCondition struct {
	// Type of condition
	Type ConditionType `json:"type"`

	// Status of the condition: True, False, Unknown
	Status string `json:"status"`

	// LastTransitionTime is the last time the condition transitioned
	// +optional
	LastTransitionTime metav1.Time `json:"lastTransitionTime,omitempty"`

	// Reason is a one-word CamelCase reason for the condition's last transition
	// +optional
	Reason string `json:"reason,omitempty"`

	// Message is a human-readable message indicating details about the transition
	// +optional
	Message string `json:"message,omitempty"`
}

// ComponentStatus represents the status of a component
type ComponentStatus struct {
	// Installed indicates if the component is installed
	Installed bool `json:"installed"`

	// Version of the installed component
	// +optional
	Version string `json:"version,omitempty"`

	// HelmRelease name
	// +optional
	HelmRelease string `json:"helmRelease,omitempty"`

	// Ready indicates if the component is ready
	Ready bool `json:"ready"`

	// Message provides additional status information
	// +optional
	Message string `json:"message,omitempty"`
}

// ComponentsStatus represents the status of all components
type ComponentsStatus struct {
	// APIServer status
	// +optional
	APIServer ComponentStatus `json:"apiserver,omitempty"`

	// Controller status
	// +optional
	Controller ComponentStatus `json:"controller,omitempty"`

	// Console status
	// +optional
	Console ComponentStatus `json:"console,omitempty"`

	// Monitoring status
	// +optional
	Monitoring ComponentStatus `json:"monitoring,omitempty"`
}

// InstallationStatus defines the observed state of Installation
type InstallationStatus struct {
	// Phase is the current phase of the installation
	// +optional
	Phase InstallationPhase `json:"phase,omitempty"`

	// Conditions represent the latest available observations of the installation state
	// +optional
	Conditions []InstallationCondition `json:"conditions,omitempty"`

	// Components status
	// +optional
	Components ComponentsStatus `json:"components,omitempty"`

	// StartTime is the time the installation started
	// +optional
	StartTime *metav1.Time `json:"startTime,omitempty"`

	// CompletionTime is the time the installation completed
	// +optional
	CompletionTime *metav1.Time `json:"completionTime,omitempty"`

	// CurrentPhase is a human-readable description of current phase
	// +optional
	CurrentPhase string `json:"currentPhase,omitempty"`

	// Message provides additional information about the installation state
	// +optional
	Message string `json:"message,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Version",type=string,JSONPath=`.spec.version`
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// Installation is the Schema for the installations API
type Installation struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   InstallationSpec   `json:"spec,omitempty"`
	Status InstallationStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// InstallationList contains a list of Installation
type InstallationList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Installation `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Installation{}, &InstallationList{})
}
