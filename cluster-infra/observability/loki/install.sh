#!/bin/bash

#####################################################################
# Loki Helm Installation Script
#
# Installs Loki using Helm chart with Garage S3 backend
#
# Prerequisites:
#   - K3s cluster running
#   - kubectl configured
#   - helm installed
#   - Garage installed and running
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
NAMESPACE="observability"
RELEASE_NAME="loki"
CHART_REPO="https://grafana.github.io/helm-charts"
CHART_NAME="grafana/loki"

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

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Please install helm first."
        print_info "Install helm: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        exit 1
    fi

    print_success "Prerequisites satisfied (kubectl and helm available)"
}

check_garage() {
    print_step "Checking Garage availability..."

    if ! kubectl get namespace garage &> /dev/null; then
        print_error "Garage namespace not found. Please install Garage first."
        exit 1
    fi

    if ! kubectl get pod -n garage -l app=garage | grep -q Running; then
        print_error "Garage is not running. Please ensure Garage is installed and running."
        exit 1
    fi

    print_success "Garage is available"
}

check_existing_installation() {
    print_step "Checking for existing installation..."

    if helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
        print_warning "Loki is already installed via Helm"
        read -p "Do you want to upgrade the existing installation? (y/N): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            UPGRADE_MODE=true
        else
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

setup_garage_bucket() {
    print_step "Setting up Garage bucket for Loki..."

    print_warning "Please create the bucket and key in Garage manually:"
    echo ""
    echo "  # Create a key for Loki"
    echo "  kubectl exec -n garage deployment/garage -- sh -c \"garage key create loki-key\""
    echo ""
    echo "  # Create the bucket"
    echo "  kubectl exec -n garage deployment/garage -- sh -c \"garage bucket create loki\""
    echo ""
    echo "  # Allow the key to access the bucket"
    echo "  kubectl exec -n garage deployment/garage -- sh -c \"garage bucket allow --read --write loki --key loki-key\""
    echo ""
    echo "  # Get the credentials"
    echo "  kubectl exec -n garage deployment/garage -- sh -c \"garage key info loki-key\""
    echo ""

    read -p "Have you created the bucket and key? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Installation cancelled. Please set up Garage first."
        exit 0
    fi

    echo ""
    read -p "Enter Garage Access Key ID: " access_key
    read -p "Enter Garage Secret Access Key: " secret_key

    if [[ -z "$access_key" || -z "$secret_key" ]]; then
        print_error "Credentials cannot be empty"
        exit 1
    fi

    # Update values.yaml with credentials
    print_info "Updating values.yaml with Garage credentials..."
    sed -i.bak "s|accessKeyId: .*|accessKeyId: $access_key|" values.yaml
    sed -i.bak "s|secretAccessKey: .*|secretAccessKey: $secret_key|" values.yaml
    rm -f values.yaml.bak

    print_success "Credentials configured in values.yaml"
}

add_helm_repo() {
    print_step "Adding Grafana Helm repository..."

    if helm repo list | grep -q "^grafana"; then
        print_info "Grafana repo already added, updating..."
        helm repo update grafana
    else
        print_info "Adding Grafana repo..."
        helm repo add grafana "$CHART_REPO"
        helm repo update
    fi

    print_success "Helm repository configured"
}

create_namespace() {
    print_step "Creating namespace..."

    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl create namespace "$NAMESPACE"
        print_success "Namespace '$NAMESPACE' created"
    else
        print_info "Namespace '$NAMESPACE' already exists"
    fi
}

install_loki() {
    print_step "Installing Loki via Helm..."

    if [[ "$UPGRADE_MODE" == "true" ]]; then
        print_info "Upgrading existing Loki installation..."
        helm upgrade "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --wait \
            --timeout 10m
    else
        print_info "Installing Loki..."
        helm install "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --create-namespace \
            --wait \
            --timeout 10m
    fi

    print_success "Loki installed successfully"
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Helm Release:"
    helm list -n "$NAMESPACE"
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki
    echo ""
    echo "Services:"
    kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=loki
    echo ""

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    echo ""
    echo "=========================================="
    print_success "Loki Installed via Helm!"
    echo "=========================================="
    echo ""
    echo "Deployment:"
    echo "  - Mode: SingleBinary (monolithic)"
    echo "  - Namespace: $NAMESPACE"
    echo "  - Release: $RELEASE_NAME"
    echo ""
    echo "Storage:"
    echo "  - Local Storage: 20Gi (7 days retention)"
    echo "  - Long-term Storage: Garage bucket 'loki'"
    echo ""
    echo "Access (via port-forward):"
    echo "  Loki Gateway:"
    echo "    kubectl port-forward -n observability svc/loki-gateway 3100:80"
    echo "    # Then access http://localhost:3100"
    echo ""
    echo "Grafana Data Source Configuration:"
    echo "  Type: Loki"
    echo "  URL: http://loki-gateway.observability.svc.cluster.local:80"
    echo ""
    echo "Next Steps:"
    echo "  1. Install Grafana (if not already installed)"
    echo "  2. Configure Grafana data source (see URL above)"
    echo "  3. Install log collector (Alloy/Promtail) later"
    echo "  4. Wait for logs to appear in Loki"
    echo ""
    echo "Helm Commands:"
    echo "  # View status"
    echo "  helm status $RELEASE_NAME -n $NAMESPACE"
    echo ""
    echo "  # Upgrade (after modifying values.yaml)"
    echo "  helm upgrade $RELEASE_NAME $CHART_NAME -n $NAMESPACE -f values.yaml"
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
    echo "  Loki Helm Installation"
    echo "=========================================="
    echo ""
    echo "This will install:"
    echo "  - Loki (via Grafana Helm chart)"
    echo "  - Garage S3 backend for storage"
    echo "  - 7 days local retention + long-term in Garage"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Release: $RELEASE_NAME"
    echo ""

    # Run installation steps
    check_prerequisites
    check_garage
    check_existing_installation

    if [[ "$UPGRADE_MODE" != "true" ]]; then
        setup_garage_bucket
    fi

    add_helm_repo
    create_namespace
    install_loki
    verify_installation
    display_installation_info

    print_success "Installation completed!"
}

# Run main function
main "$@"
