#!/bin/bash

#####################################################################
# nginx-ingress Uninstallation Script
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

# Configuration
NGINX_VERSION="${NGINX_VERSION:-v1.10.0}"

echo "=========================================="
echo "  nginx-ingress Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove nginx-ingress from your cluster"
read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Uninstalling nginx-ingress..."
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml --ignore-not-found=true

print_info "Cleaning up namespace..."
kubectl delete namespace ingress-nginx --ignore-not-found=true

print_success "nginx-ingress has been uninstalled"
