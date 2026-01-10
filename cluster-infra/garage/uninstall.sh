#!/bin/bash

#####################################################################
# Garage Uninstallation Script
#####################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
echo "  Garage Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove Garage from your cluster"
print_warning "Data on /mnt/garage-data will NOT be deleted"
echo ""
read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Uninstalling Garage..."

# Try standalone mode first
if kubectl get namespace garage &> /dev/null; then
    kubectl delete -f standalone/ingress.yaml --ignore-not-found=true
    kubectl delete -f standalone/service.yaml --ignore-not-found=true
    kubectl delete -f standalone/deployment.yaml --ignore-not-found=true
    kubectl delete -f standalone/pv-pvc.yaml --ignore-not-found=true
    kubectl delete -f standalone/secret.yaml --ignore-not-found=true
    kubectl delete -f standalone/namespace.yaml --ignore-not-found=true
fi

# Try distributed mode
kubectl delete -f distributed/ --ignore-not-found=true 2>/dev/null || true

print_success "Garage has been uninstalled"
echo ""
print_info "Data preserved at /mnt/garage-data on the master node"
print_info "To completely remove:"
echo "  sudo rm -rf /mnt/garage-data"
echo ""
