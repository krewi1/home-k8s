#!/bin/bash

#####################################################################
# Prometheus + Thanos Uninstallation Script
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
echo "  Observability Stack Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove Prometheus and Thanos from your cluster"
print_warning "Data on /mnt/k8s-pvc/prometheus will NOT be deleted"
print_warning "Data in MinIO bucket 'thanos' will NOT be deleted"
echo ""

read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Uninstalling observability stack..."

if kubectl get namespace observability &> /dev/null; then
    print_info "Removing Thanos components..."
    kubectl delete -f compactor.yaml --ignore-not-found=true
    kubectl delete -f query.yaml --ignore-not-found=true
    kubectl delete -f store-gateway.yaml --ignore-not-found=true

    print_info "Removing Prometheus..."
    kubectl delete -f service.yaml --ignore-not-found=true
    kubectl delete -f deployment.yaml --ignore-not-found=true
    kubectl delete -f minio-secret.yaml --ignore-not-found=true
    kubectl delete -f pv-pvc.yaml --ignore-not-found=true
    kubectl delete -f configmap.yaml --ignore-not-found=true
    kubectl delete -f rbac.yaml --ignore-not-found=true
    kubectl delete -f namespace.yaml --ignore-not-found=true
fi

print_success "Observability stack has been uninstalled"
echo ""
print_info "Data preserved (manual cleanup required):"
echo "  - /mnt/k8s-pvc/prometheus on master node"
echo "  - MinIO bucket 'thanos'"
echo ""
print_info "To fully clean up:"
echo ""
echo "  # Remove Prometheus data"
echo "  sudo rm -rf /mnt/k8s-pvc/prometheus"
echo ""
echo "  # Remove MinIO bucket"
echo "  kubectl run -n minio mc-cleanup --image=minio/mc --rm -i --command -- sh -c \\"
echo "    mc alias set myminio http://minio.minio:9000 admin changeme123 && \\"
echo "    mc rb --force myminio/thanos\\"
