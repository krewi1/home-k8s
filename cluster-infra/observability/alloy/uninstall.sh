#!/bin/bash

#####################################################################
# Grafana Alloy Helm Uninstallation Script
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
RELEASE_NAME="alloy"

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
echo "  Grafana Alloy Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove Alloy from your cluster"
print_warning "Log collection will stop"
echo ""

read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Uninstalling Alloy Helm release..."

if helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
    print_info "Removing Helm release '$RELEASE_NAME'..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
    print_success "Helm release removed"
else
    print_warning "Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
fi

print_info "Removing ConfigMap..."
kubectl delete configmap alloy-config -n "$NAMESPACE" --ignore-not-found=true

print_success "Grafana Alloy has been uninstalled"
echo ""
print_info "Log collection has stopped. To resume:"
echo "  ./install.sh"
echo ""
