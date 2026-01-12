#!/bin/bash

#####################################################################
# Grafana Helm Uninstallation Script
#####################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="observability"
RELEASE_NAME="grafana"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "=========================================="
echo "  Grafana Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove Grafana from your cluster"
print_warning "Dashboards and settings stored in PVC will be preserved"
echo ""

read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Uninstalling Grafana Helm release..."

if helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
    print_info "Removing Helm release '$RELEASE_NAME'..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
    print_success "Helm release removed"
else
    print_warning "Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
fi

print_success "Grafana has been uninstalled"
echo ""
print_info "Data preserved (manual cleanup required):"
echo "  - PVC in namespace '$NAMESPACE' (contains dashboards and settings)"
echo ""
print_info "To fully clean up:"
echo ""
echo "  # Remove PVC (WARNING: deletes all dashboards and settings)"
echo "  kubectl delete pvc -n $NAMESPACE -l app.kubernetes.io/name=grafana"
echo ""
