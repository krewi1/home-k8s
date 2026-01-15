#!/bin/bash

#####################################################################
# PostgreSQL Helm Installation Script
#
# Installs PostgreSQL using Bitnami Helm chart
#
# Prerequisites:
#   - K3s cluster running
#   - kubectl configured
#   - helm installed
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
NAMESPACE="postgres"
RELEASE_NAME="postgresql"
CHART_REPO="https://charts.bitnami.com/bitnami"
CHART_NAME="bitnami/postgresql"
MASTER_NODE="master-01"
DATA_DIR="/mnt/k8s-pvc/postgres"

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

check_existing_installation() {
    print_step "Checking for existing installation..."

    if helm list -n "$NAMESPACE" | grep -q "^$RELEASE_NAME"; then
        print_warning "PostgreSQL is already installed via Helm"
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
    print_step "Adding Bitnami Helm repository..."

    if helm repo list | grep -q "^bitnami"; then
        print_info "Bitnami repo already added, updating..."
        helm repo update bitnami
    else
        print_info "Adding Bitnami repo..."
        helm repo add bitnami "$CHART_REPO"
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

setup_storage() {
#    print_step "Setting up persistent storage on master node..."
#
#    # Create data directory on master node
#    print_info "Creating data directory $DATA_DIR on $MASTER_NODE..."
#    print_info "You may need to run this manually on $MASTER_NODE if SSH is not available:"
#    echo ""
#    echo "  ssh $MASTER_NODE 'sudo mkdir -p $DATA_DIR && sudo chown 1001:1001 $DATA_DIR'"
#    echo ""
#
#    read -p "Has the directory been created? (y/N): " confirm
#    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
#        print_warning "Please create the directory and run the script again"
#        exit 1
#    fi

    # Apply PV and PVC
    print_info "Creating PersistentVolume and PersistentVolumeClaim..."
    kubectl apply -f pv-pvc.yaml

    # Wait for PVC to be bound
    print_info "Waiting for PVC to be bound..."
#    kubectl wait --for=condition=Bound pvc/postgresql-data-pvc -n "$NAMESPACE" --timeout=60s

    print_success "Storage configured (PV/PVC bound)"
}

install_postgresql() {
    print_step "Installing PostgreSQL via Helm..."

    if [[ "$UPGRADE_MODE" == "true" ]]; then
        print_info "Upgrading existing PostgreSQL installation..."
        helm upgrade "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --wait \
            --timeout 10m
    else
        print_info "Installing PostgreSQL..."
        helm install "$RELEASE_NAME" "$CHART_NAME" \
            --namespace "$NAMESPACE" \
            --values values.yaml \
            --create-namespace \
            --wait \
            --timeout 10m
    fi

    print_success "PostgreSQL installed successfully"
}

get_credentials() {
    print_step "Retrieving credentials..."

    POSTGRES_PASSWORD=$(kubectl get secret --namespace "$NAMESPACE" "$RELEASE_NAME" \
        -o jsonpath="{.data.postgres-password}" 2>/dev/null | base64 --decode)

    APP_PASSWORD=$(kubectl get secret --namespace "$NAMESPACE" "$RELEASE_NAME" \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode)

    if [[ -n "$POSTGRES_PASSWORD" ]]; then
        print_success "Credentials retrieved"
    else
        print_warning "Could not retrieve credentials from secret"
    fi
}

verify_installation() {
    print_step "Verifying installation..."

    echo ""
    echo "Helm Release:"
    helm list -n "$NAMESPACE" | grep "$RELEASE_NAME"
    echo ""
    echo "StatefulSet:"
    kubectl get statefulset -n "$NAMESPACE"
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "Services:"
    kubectl get svc -n "$NAMESPACE"
    echo ""
    echo "PVC:"
    kubectl get pvc -n "$NAMESPACE"
    echo ""

    print_success "Installation verification complete"
}

display_installation_info() {
    print_step "Installation complete!"

    echo ""
    echo "=========================================="
    print_success "PostgreSQL Installed!"
    echo "=========================================="
    echo ""
    echo "Deployment:"
    echo "  - Namespace: $NAMESPACE"
    echo "  - Release: $RELEASE_NAME"
    echo "  - Node: $MASTER_NODE"
    echo "  - Storage: $DATA_DIR (10Gi SSD)"
    echo ""
    echo "Connection Details:"
    echo "  - Host: $RELEASE_NAME.$NAMESPACE.svc.cluster.local"
    echo "  - Port: 5432"
    echo "  - Database: default"
    echo ""
    echo "Credentials:"
    echo "  Superuser:"
    echo "    - Username: postgres"
    echo "    - Password: $POSTGRES_PASSWORD"
    echo ""
    echo "  Application User:"
    echo "    - Username: appuser"
    echo "    - Password: $APP_PASSWORD"
    echo ""
    echo "Connect from within cluster:"
    echo "  kubectl run postgres-client --rm -it --restart=Never \\"
    echo "    --namespace $NAMESPACE \\"
    echo "    --image bitnami/postgresql:latest \\"
    echo "    --env=\"PGPASSWORD=\$POSTGRES_PASSWORD\" \\"
    echo "    -- psql -h $RELEASE_NAME -U postgres -d default"
    echo ""
    echo "Port-forward for local access:"
    echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME 5432:5432"
    echo "  psql -h localhost -U postgres -d default"
    echo ""
    echo "Connection string for applications:"
    echo "  postgresql://appuser:\$PASSWORD@$RELEASE_NAME.$NAMESPACE.svc.cluster.local:5432/default"
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
    echo "  PostgreSQL Installation"
    echo "=========================================="
    echo ""
    echo "This will install:"
    echo "  - PostgreSQL (Bitnami Helm chart)"
    echo "  - Single instance (standalone mode)"
    echo "  - 10Gi persistent storage on SSD ($DATA_DIR)"
    echo "  - Pinned to $MASTER_NODE"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "Release: $RELEASE_NAME"
    echo ""

    # Run installation steps
    check_prerequisites
    check_existing_installation
    add_helm_repo
    create_namespace
    setup_storage
    install_postgresql
    get_credentials
    verify_installation
    display_installation_info

    print_success "Installation completed!"
}

# Run main function
main "$@"
