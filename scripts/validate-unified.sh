#!/bin/bash

# Validate the unified helm chart structure

set -e

echo "==================== Validating Unified Chart ===================="
cd "$(dirname "$0")/.."

# Check if required directories exist
echo "1. Checking directory structure..."
required_dirs=("edge-controller/templates/crds" "edge-controller/templates/chartmuseum" "edge-controller/templates/controller" "edge-controller/templates/components" "edge-controller/templates/hooks")
for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir exists"
    else
        echo "  ✗ $dir missing"
        exit 1
    fi
done

# Check if required files exist
echo ""
echo "2. Checking required files..."
required_files=("edge-controller/values.yaml" "edge-controller/templates/_helpers.tpl")
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file exists"
    else
        echo "  ✗ $file missing"
        exit 1
    fi
done

# Check if templates are valid
echo ""
echo "3. Checking Helm chart validity..."
if helm lint edge-controller; then
    echo "  ✓ Helm chart is valid"
else
    echo "  ✗ Helm chart validation failed"
    exit 1
fi

# Test template rendering for different modes
echo ""
echo "4. Testing template rendering..."
modes=("all" "host" "member" "none")
for mode in "${modes[@]}"; do
    echo "  Testing mode: $mode"
    if helm template test-$mode edge-controller --set global.mode=$mode > /dev/null 2>&1; then
        echo "    ✓ $mode mode renders successfully"
    else
        echo "    ✗ $mode mode rendering failed"
        helm template test-$mode edge-controller --set global.mode=$mode
        exit 1
    fi
done

# Check component CR generation
echo ""
echo "5. Checking Component CR generation..."
echo "  Testing host mode components..."
# Get expected component count from template files
expected_components=$(ls -1 edge-controller/templates/components/*.yaml 2>/dev/null | wc -l)
components=$(helm template test-host edge-controller --set global.mode=host | grep "kind: Component" | wc -l)
if [ "$components" -gt 0 ]; then
    echo "    ✓ Component CRs generated ($components components found, $expected_components templates available)"
    # List actual components
    component_names=$(helm template test-host edge-controller --set global.mode=host | grep -A1 "kind: Component" | grep "name:" | awk '{print $2}' | tr '\n' ', ' | sed 's/,$//')
    echo "    Components: $component_names"
else
    echo "    ✗ No Component CRs found"
    exit 1
fi

echo ""
echo "6. Checking ChartMuseum templates..."
if [ -f "edge-controller/templates/chartmuseum/deployment.yaml" ] && [ -f "edge-controller/templates/chartmuseum/service.yaml" ]; then
    echo "    ✓ ChartMuseum templates exist"
else
    echo "    ✗ ChartMuseum templates missing"
    exit 1
fi

echo ""
echo "7. Checking Component CR templates..."
component_templates=("controller.yaml" "apiserver.yaml" "console.yaml" "monitoring.yaml")
for template in "${component_templates[@]}"; do
    if [ -f "edge-controller/templates/components/$template" ]; then
        echo "    ✓ $template exists"
    else
        echo "    ✗ $template missing"
        exit 1
    fi
done

echo ""
echo "✅ All validations passed!"
echo ""
echo "The unified helm chart is ready for use."
echo ""
echo "Quick start commands:"
echo "  make install-all          # Install all components"
echo "  make install-host         # Install host cluster"
echo "  make install-member       # Install member cluster"