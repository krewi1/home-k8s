#!/bin/bash

#####################################################################
# Grafana Alloy Helm Installation Script
#
# Installs Grafana Alloy as a DaemonSet for log collection
#
# Prerequisites:
#   - K3s cluster running
#   - kubectl configured
#   - helm installed
#   - Loki installed and running
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
RELEASE_NAME="alloy"
CHART_REPO="https://grafana.github.io/helm-charts"
CHART_NAME="grafana/alloy"

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

check_loki() {
    print_step "Checking Loki availability..."

    if ! kubectl get deployment -n observability loki &> /dev/null && \
       ! helm list -n observability | grep -q "^loki"; then
        print_error "Loki is not installed. Please install Loki first."
        print_info "Run: cd ../loki && ./install.sh"
        exit 1
    fi

    print_success "Loki is available"
}

check_existing_installation() {
    print_step "Checking for existing installation..."

    if helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
        print_warning "Alloy is already installed via Helm"
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

create_configmap() {
    print_step "Creating Alloy configuration ConfigMap..."

    kubectl apply -f configmap.yaml

    print_success "ConfigMap created"
}

install_alloy() {
    print_step "Installing Alloy via Helm..."

    if [[ "$UPGRADE_MODE" == "true" ]]; then
        print_info "Upgrading existing Alloy installation..."
        helm upgrade "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --set alloy.configMap.name=alloy-config \
            --wait \
            --timeout 5m
    else
        print_info "Installing Alloy..."
        helm install "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --set alloy.configMap.name=alloy-config \
            --create-namespace \
            --wait \
            --timeout 5m
    fi

    print_success "Alloy installed successfully"
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Helm Release:"
    helm list -n "$NAMESPACE" | grep "$RELEASE_NAME"
    echo ""
    echo "DaemonSet:"
    kubectl get daemonset -n "$NAMESPACE" -l app.kubernetes.io/name=alloy
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=alloy
    echo ""

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    echo ""
    echo "=========================================="
    print_success "Grafana Alloy Installed!"
    echo "=========================================="
    echo ""
    echo "Deployment:"
    echo "  - Mode: DaemonSet (runs on every node)"
    echo "  - Namespace: $NAMESPACE"
    echo "  - Release: $RELEASE_NAME"
    echo ""
    echo "Log Collection:"
    echo "  - Source: All Kubernetes pods"
    echo "  - Destination: Loki (loki-gateway.observability)"
    echo "  - Labels: namespace, pod, container, app, job, cluster"
    echo ""
    echo "Check Status:"
    echo "  # View all Alloy pods"
    echo "  kubectl get pods -n observability -l app.kubernetes.io/name=alloy"
    echo ""
    echo "  # View logs from Alloy"
    echo "  kubectl logs -n observability -l app.kubernetes.io/name=alloy -f"
    echo ""
    echo "  # Check if logs are being sent to Loki"
    echo "  kubectl logs -n observability -l app.kubernetes.io/name=alloy | grep 'loki.write'"
    echo ""
    echo "Helm Commands:"
    echo "  # View status"
    echo "  helm status $RELEASE_NAME -n $NAMESPACE"
    echo ""
    echo "  # Upgrade (after modifying config)"
    echo "  kubectl apply -f configmap.yaml"
    echo "  helm upgrade $RELEASE_NAME $CHART_NAME -n $NAMESPACE -f values.yaml --set alloy.configMap.name=alloy-config"
    echo ""
    echo "  # Uninstall"
    echo "  ./uninstall.sh"
    echo ""
    echo "Next Steps:"
    echo "  1. Wait 1-2 minutes for log collection to start"
    echo "  2. Check Grafana - logs should appear in Loki data source"
    echo "  3. Query logs with LogQL: {namespace=\"default\"}"
    echo ""
    echo "=========================================="
}

#####################################################################
# Main Script
#####################################################################

main() {
    clear
    echo "=========================================="
    echo "  Grafana Alloy Installation"
    echo "=========================================="
    echo ""
    echo "This will install:"
    echo "  - Grafana Alloy (DaemonSet for log collection)"
    echo "  - Collects logs from all Kubernetes pods"
    echo "  - Sends logs to Loki"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Release: $RELEASE_NAME"
    echo ""

    # Run installation steps
    check_prerequisites
    check_loki
    check_existing_installation
    add_helm_repo
    create_namespace
    create_configmap
    install_alloy
    verify_installation
    display_installation_info

    print_success "Installation completed!"
}

# Run main function
main "$@"
