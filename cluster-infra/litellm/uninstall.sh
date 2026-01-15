#!/bin/bash

#####################################################################
# LiteLLM Uninstallation Script
#####################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="litellm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo "  LiteLLM Uninstallation"
echo "=========================================="
echo ""

print_warning "This will remove LiteLLM from your cluster"
print_warning "Database data in PostgreSQL will be preserved"
echo ""

read -p "Are you sure you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

print_info "Removing LiteLLM resources..."

kubectl delete -f "$SCRIPT_DIR/service.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/deployment.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/configmap.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/secret.yaml" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/namespace.yaml" --ignore-not-found

print_success "LiteLLM has been uninstalled"
echo ""
print_info "Data preserved in PostgreSQL:"
echo "  - Database: litellm"
echo "  - User: litellm"
echo ""
print_info "To fully clean up the database:"
echo ""
echo "  kubectl port-forward -n postgres svc/postgresql 5432:5432"
echo "  psql -h localhost -U postgres -c 'DROP DATABASE litellm;'"
echo "  psql -h localhost -U postgres -c 'DROP USER litellm;'"
echo ""
