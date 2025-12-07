package phases

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"strings"

	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/serializer/yaml"
	"k8s.io/client-go/rest"
	"k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"

	installerv1alpha1 "github.com/theriseunion/installer/api/v1alpha1"
)

//go:embed crds/*.yaml
var crdFiles embed.FS

// CRDInstaller handles CRD installation
type CRDInstaller struct {
	client client.Client
	config *rest.Config
}

// NewCRDInstaller creates a new CRD installer
func NewCRDInstaller(k8sClient client.Client, config *rest.Config) *CRDInstaller {
	return &CRDInstaller{
		client: k8sClient,
		config: config,
	}
}

// Install installs all required CRDs
func (i *CRDInstaller) Install(ctx context.Context, installation *installerv1alpha1.Installation) error {
	klog.Info("Installing CRDs...")

	// Read all CRD files from embedded filesystem
	crds, err := i.loadCRDs()
	if err != nil {
		return fmt.Errorf("failed to load CRDs: %w", err)
	}

	klog.Infof("Found %d CRDs to install", len(crds))

	// Install each CRD
	for _, crd := range crds {
		if err := i.installCRD(ctx, crd); err != nil {
			return fmt.Errorf("failed to install CRD %s: %w", crd.GetName(), err)
		}
		klog.Infof("CRD %s installed successfully", crd.GetName())
	}

	klog.Info("All CRDs installed successfully")
	return nil
}

// loadCRDs loads all CRD definitions from embedded files
func (i *CRDInstaller) loadCRDs() ([]*apiextensionsv1.CustomResourceDefinition, error) {
	var crds []*apiextensionsv1.CustomResourceDefinition

	// Walk through the embedded CRD directory
	err := fs.WalkDir(crdFiles, "crds", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		// Skip directories and non-YAML files
		if d.IsDir() || !strings.HasSuffix(path, ".yaml") {
			return nil
		}

		// Read CRD file
		data, err := crdFiles.ReadFile(path)
		if err != nil {
			return fmt.Errorf("failed to read CRD file %s: %w", path, err)
		}

		// Decode YAML to CRD object
		crd, err := i.decodeCRD(data)
		if err != nil {
			return fmt.Errorf("failed to decode CRD from %s: %w", path, err)
		}

		crds = append(crds, crd)
		return nil
	})

	if err != nil {
		return nil, err
	}

	return crds, nil
}

// decodeCRD decodes YAML data into a CRD object
func (i *CRDInstaller) decodeCRD(data []byte) (*apiextensionsv1.CustomResourceDefinition, error) {
	// Create a YAML decoder
	decoder := yaml.NewDecodingSerializer(unstructured.UnstructuredJSONScheme)

	// Decode to unstructured object
	obj := &unstructured.Unstructured{}
	_, _, err := decoder.Decode(data, nil, obj)
	if err != nil {
		return nil, err
	}

	// Convert to CRD
	crd := &apiextensionsv1.CustomResourceDefinition{}
	if err := i.client.Scheme().Convert(obj, crd, nil); err != nil {
		return nil, err
	}

	return crd, nil
}

// installCRD installs or updates a single CRD
func (i *CRDInstaller) installCRD(ctx context.Context, crd *apiextensionsv1.CustomResourceDefinition) error {
	// Check if CRD already exists
	existing := &apiextensionsv1.CustomResourceDefinition{}
	err := i.client.Get(ctx, client.ObjectKey{Name: crd.Name}, existing)

	if err != nil {
		if errors.IsNotFound(err) {
			// Create new CRD
			klog.Infof("Creating CRD: %s", crd.Name)
			if err := i.client.Create(ctx, crd); err != nil {
				return fmt.Errorf("failed to create CRD: %w", err)
			}
			return nil
		}
		return err
	}

	// Update existing CRD
	klog.Infof("Updating existing CRD: %s", crd.Name)
	existing.Spec = crd.Spec
	if err := i.client.Update(ctx, existing); err != nil {
		return fmt.Errorf("failed to update CRD: %w", err)
	}

	return nil
}
