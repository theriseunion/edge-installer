#!/bin/bash

# Build ChartMuseum image with edge-platform charts

set -e

# Default values
REGISTRY=${REGISTRY:-"quanzhenglong.com/edge"}
TAG=${TAG:-"latest"}
OUTPUT_DIR=${OUTPUT_DIR:-"bin/_output"}

echo "==================== Building ChartMuseum Image ===================="
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo "Output: $OUTPUT_DIR"
echo "================================================================"

# Clean and create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Package all component charts
echo ""
echo "=== Packaging Helm Charts ==="
cd "$(dirname "$0")/.."

# List of component charts to package
CHARTS=("edge-apiserver" "edge-console" "edge-controller" "edge-monitoring" "kubeedge" "monitoring-service" "vcluster" "yurt-manager" "yurthub")

for chart in "${CHARTS[@]}"; do
    if [ -d "$chart" ]; then
        echo "Packaging $chart..."
        helm package "$chart" -d "$OUTPUT_DIR"
    else
        echo "Warning: Chart directory $chart not found, skipping..."
    fi
done

# Show packaged charts
echo ""
echo "=== Packaged Charts ==="
ls -lh "$OUTPUT_DIR"/*.tgz 2>/dev/null || echo "No charts packaged"

# Build ChartMuseum image
echo ""
echo "=== Building ChartMuseum Image ==="
MUSEUM_IMG="$REGISTRY/edge-museum:$TAG"
echo "Building image: $MUSEUM_IMG"

docker build -f Dockerfile.museum -t "$MUSEUM_IMG" .

echo ""
echo "✅ ChartMuseum image built successfully: $MUSEUM_IMG"
echo ""
echo "To push the image, run:"
echo "  docker push $MUSEUM_IMG"
echo ""
echo "To use the unified installation, run:"
echo "  make install-all"
echo "  or"
echo "  helm install edge-platform ./edge-controller"