#!/bin/bash

#####################################################################
# PostgreSQL Helm Uninstallation Script
#####################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="postgres"
RELEASE_NAME="postgresql"

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
echo "  PostgreSQL Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove PostgreSQL from your cluster"
print_warning "Data stored in PVC will be preserved by default"
echo ""

read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Uninstalling PostgreSQL Helm release..."

if helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
    print_info "Removing Helm release '$RELEASE_NAME'..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
    print_success "Helm release removed"
else
    print_warning "Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
fi

print_success "PostgreSQL has been uninstalled"
echo ""
print_info "Data preserved (manual cleanup required):"
echo "  - PVC: postgresql-data-pvc in namespace '$NAMESPACE'"
echo "  - PV: postgresql-data-pv"
echo "  - Data: /mnt/k8s-pvc/postgres on master-01"
echo ""
print_info "To fully clean up (WARNING: deletes all data):"
echo ""
echo "  # Remove PVC and PV"
echo "  kubectl delete pvc -n $NAMESPACE postgresql-data-pvc"
echo "  kubectl delete pv postgresql-data-pv"
echo ""
echo "  # Remove data directory on master-01"
echo "  ssh master-01 'sudo rm -rf /mnt/k8s-pvc/postgres'"
echo ""
echo "  # Remove namespace"
echo "  kubectl delete namespace $NAMESPACE"
echo ""
