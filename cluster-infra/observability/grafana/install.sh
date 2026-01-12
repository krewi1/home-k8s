#!/bin/bash

#####################################################################
# Grafana Helm Installation Script
#
# Installs Grafana with pre-configured datasources for:
#   - Prometheus (via Thanos Query)
#   - Loki (logs)
#
# Prerequisites:
#   - K3s cluster running
#   - kubectl configured
#   - helm installed
#   - Prometheus/Thanos installed
#   - Loki installed
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
RELEASE_NAME="grafana"
CHART_REPO="https://grafana.github.io/helm-charts"
CHART_NAME="grafana/grafana"

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

check_datasources() {
    print_step "Checking datasource availability..."

    local all_ok=true

    # Check Thanos Query
    if kubectl get service thanos-query -n observability &> /dev/null; then
        print_success "Thanos Query service found"
    else
        print_warning "Thanos Query service not found (Prometheus datasource may not work)"
        all_ok=false
    fi

    # Check Loki
    if kubectl get service loki-gateway -n observability &> /dev/null; then
        print_success "Loki Gateway service found"
    else
        print_warning "Loki Gateway service not found (Loki datasource may not work)"
        all_ok=false
    fi

    if [[ "$all_ok" == "false" ]]; then
        echo ""
        read -p "Some datasources are not available. Continue anyway? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

check_existing_installation() {
    print_step "Checking for existing installation..."

    if helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
        print_warning "Grafana is already installed via Helm"
        read -p "Do you want to upgrade the existing installation? (y/N): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            UPGRADE_MODE=true
        else
            print_info "Installation cancelled"
            exit 0
        fi
    fi
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

install_grafana() {
    print_step "Installing Grafana via Helm..."

    if [[ "$UPGRADE_MODE" == "true" ]]; then
        print_info "Upgrading existing Grafana installation..."
        helm upgrade "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --wait \
            --timeout 10m
    else
        print_info "Installing Grafana..."
        helm install "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --create-namespace \
            --wait \
            --timeout 10m
    fi

    print_success "Grafana installed successfully"
}

get_admin_password() {
    print_step "Retrieving admin password..."

    local password
    password=$(kubectl get secret --namespace "$NAMESPACE" "$RELEASE_NAME" \
        -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode)

    if [[ -n "$password" ]]; then
        ADMIN_PASSWORD="$password"
        print_success "Admin password retrieved"
    else
        ADMIN_PASSWORD="admin"
        print_warning "Could not retrieve password, using default: admin"
    fi
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Helm Release:"
    helm list -n "$NAMESPACE" | grep "$RELEASE_NAME"
    echo ""
    echo "Deployment:"
    kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
    echo ""
    echo "Services:"
    kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
    echo ""

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    echo ""
    echo "=========================================="
    print_success "Grafana Installed!"
    echo "=========================================="
    echo ""
    echo "Deployment:"
    echo "  - Namespace: $NAMESPACE"
    echo "  - Release: $RELEASE_NAME"
    echo ""
    echo "Pre-configured Datasources:"
    echo "  ✓ Prometheus (via Thanos Query)"
    echo "    URL: http://thanos-query.observability.svc.cluster.local:9090"
    echo "  ✓ Loki (logs)"
    echo "    URL: http://loki-gateway.observability.svc.cluster.local:80"
    echo ""
    echo "Pre-installed Dashboards:"
    echo "  ✓ Kubernetes Cluster Monitoring (ID: 315)"
    echo "  ✓ Kubernetes Pods (ID: 6417)"
    echo "  ✓ Node Exporter Full (ID: 1860)"
    echo "  ✓ Loki Logs (ID: 13639)"
    echo ""
    echo "Access Grafana:"
    echo "  1. Via Ingress (Recommended):"
    echo "     http://grafana.home"
    echo ""
    echo "     Add to /etc/hosts (or configure DNS):"
    echo "     <your-node-ip> grafana.home"
    echo ""
    echo "  2. Via Port-forward (Alternative):"
    echo "     kubectl port-forward -n observability svc/grafana 3000:80"
    echo "     http://localhost:3000"
    echo ""
    echo "  3. Login credentials:"
    echo "     Username: admin"
    echo "     Password: $ADMIN_PASSWORD"
    echo ""
    echo "Quick Start:"
    echo "  • Explore → Select 'Loki' → Query logs: {namespace=\"default\"}"
    echo "  • Explore → Select 'Prometheus' → Query metrics: up"
    echo "  • Dashboards → Browse → Select pre-installed dashboards"
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
    echo "  Grafana Installation"
    echo "=========================================="
    echo ""
    echo "This will install:"
    echo "  - Grafana (visualization platform)"
    echo "  - Pre-configured datasources (Prometheus + Loki)"
    echo "  - Pre-installed Kubernetes dashboards"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Release: $RELEASE_NAME"
    echo ""

    # Run installation steps
    check_prerequisites
    check_datasources
    check_existing_installation
    add_helm_repo
    create_namespace
    install_grafana
    get_admin_password
    verify_installation
    display_installation_info

    print_success "Installation completed!"
}

# Run main function
main "$@"
