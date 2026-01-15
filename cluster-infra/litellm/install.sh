#!/bin/bash

#####################################################################
# LiteLLM Installation Script
#
# Installs LiteLLM proxy with PostgreSQL backend
#
# Prerequisites:
#   - K3s cluster running
#   - kubectl configured
#   - PostgreSQL installed and database created (see pg-setup.sql)
#####################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
NAMESPACE="litellm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#####################################################################
# Helper Functions
#####################################################################

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${CYAN}==>${NC} $1"
}

check_prerequisites() {
    print_step "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    print_success "Prerequisites satisfied"
}

check_postgres() {
    print_step "Checking PostgreSQL availability..."

    if kubectl get svc postgresql -n postgres &> /dev/null; then
        print_success "PostgreSQL service found"
    else
        print_error "PostgreSQL service not found in 'postgres' namespace"
        print_info "Please install PostgreSQL first: cd ../postgres && ./install.sh"
        exit 1
    fi

    echo ""
    print_warning "Have you created the LiteLLM database and user?"
    echo ""
    echo "  Run the following to set up the database:"
    echo ""
    echo "  1. Port-forward to PostgreSQL:"
    echo "     kubectl port-forward -n postgres svc/postgresql 5432:5432"
    echo ""
    echo "  2. In another terminal, run:"
    echo "     psql -h localhost -U postgres -f $SCRIPT_DIR/pg-setup.sql"
    echo ""
    echo "  Or connect and run manually:"
    echo "     psql -h localhost -U postgres"
    echo "     \\i $SCRIPT_DIR/pg-setup.sql"
    echo ""

    read -p "Has the database been created? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "Please create the database and run the script again"
        exit 1
    fi
}

check_secrets() {
    print_step "Checking secrets configuration..."

    print_warning "Please ensure you have updated secret.yaml with:"
    echo "  - DATABASE_URL: PostgreSQL connection string with correct password"
    echo "  - LITELLM_MASTER_KEY: Secure master key for API access"
    echo "  - API keys for your LLM providers (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.)"
    echo ""

    read -p "Have you updated the secrets? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "Please update secret.yaml and run the script again"
        exit 1
    fi
}

apply_manifests() {
    print_step "Applying Kubernetes manifests..."

    print_info "Creating namespace..."
    kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

    print_info "Creating secrets..."
    kubectl apply -f "$SCRIPT_DIR/secret.yaml"

    print_info "Creating ConfigMap..."
    kubectl apply -f "$SCRIPT_DIR/configmap.yaml"

    print_info "Creating Deployment and Service..."
    kubectl apply -f "$SCRIPT_DIR/deployment.yaml"
    kubectl apply -f "$SCRIPT_DIR/service.yaml"

    print_success "All manifests applied"
}

wait_for_deployment() {
    print_step "Waiting for LiteLLM to be ready..."

    kubectl wait --for=condition=available --timeout=300s \
        deployment/litellm -n "$NAMESPACE"

    print_success "LiteLLM is ready"
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Deployment:"
    kubectl get deployment -n "$NAMESPACE"
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "Services:"
    kubectl get svc -n "$NAMESPACE"
    echo ""
    echo "Ingress:"
    kubectl get ingress -n "$NAMESPACE"
    echo ""

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    local master_key=$(kubectl get secret -n "$NAMESPACE" litellm-secrets \
        -o jsonpath='{.data.LITELLM_MASTER_KEY}' 2>/dev/null | base64 --decode)

    echo ""
    echo "=========================================="
    print_success "LiteLLM Installed!"
    echo "=========================================="
    echo ""
    echo "Deployment:"
    echo "  - Namespace: $NAMESPACE"
    echo "  - Service: litellm.$NAMESPACE.svc.cluster.local:4000"
    echo ""
    echo "Access:"
    echo "  - Ingress: http://litellm.home"
    echo "  - Port-forward: kubectl port-forward -n $NAMESPACE svc/litellm 4000:4000"
    echo ""
    echo "Master Key: $master_key"
    echo ""
    echo "Test the API:"
    echo "  curl http://litellm.home/health"
    echo ""
    echo "  curl http://litellm.home/v1/models \\"
    echo "    -H \"Authorization: Bearer $master_key\""
    echo ""
    echo "OpenAI-compatible endpoint:"
    echo "  curl http://litellm.home/v1/chat/completions \\"
    echo "    -H \"Authorization: Bearer $master_key\" \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"model\": \"gpt-4o-mini\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"
    echo ""
    echo "UI Dashboard:"
    echo "  http://litellm.home/ui"
    echo ""
    echo "Helm Commands:"
    echo "  # View logs"
    echo "  kubectl logs -n $NAMESPACE -l app=litellm -f"
    echo ""
    echo "  # Restart"
    echo "  kubectl rollout restart deployment/litellm -n $NAMESPACE"
    echo ""
    echo "  # Uninstall"
    echo "  ./uninstall.sh"
    echo ""
    echo "=========================================="
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  LiteLLM Installation"
    echo "=========================================="
    echo ""
    echo "This will install:"
    echo "  - LiteLLM Proxy (OpenAI-compatible API gateway)"
    echo "  - Connected to PostgreSQL for key management"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo ""

    check_prerequisites
    check_secrets
    apply_manifests
    wait_for_deployment
    verify_installation
    display_installation_info

    print_success "Installation completed!"
}

# Run main function
main "$@"
