#!/bin/bash

#####################################################################
# DNS Configuration Setup Script
#
# This script configures dnsmasq on the Raspberry Pi 4
# for the .home domain resolution
#
# Network Configuration:
#   nginx/DNS (Pi 4):  192.168.0.221
#   master-01 (Pi 5):  192.168.0.222
#   worker-01 (Pi 5):  192.168.0.223
#   worker-02 (Pi 5):  192.168.0.224
#   worker-03 (Pi 4):  192.168.0.225
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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0 $*"
        exit 1
    fi
}

show_config() {
    echo ""
    echo "=========================================="
    echo "  DNS Configuration Setup"
    echo "=========================================="
    echo ""
    print_info "Network Configuration:"
    echo "  nginx/DNS (Pi 4):  192.168.0.221"
    echo "  master-01 (Pi 5):  192.168.0.222"
    echo "  worker-01 (Pi 5):  192.168.0.223"
    echo "  worker-02 (Pi 5):  192.168.0.224"
    echo "  worker-03 (Pi 4):  192.168.0.225"
    echo ""
    print_info "All *.home domains will resolve to 192.168.0.221 (nginx)"
    echo ""
}

# Install dnsmasq
install_dnsmasq() {
    print_info "Checking if dnsmasq is installed..."

    if command -v dnsmasq >/dev/null 2>&1; then
        print_success "dnsmasq is already installed"
        dnsmasq --version | head -1
    else
        print_info "Installing dnsmasq..."
        apt update
        apt install -y dnsmasq
        print_success "dnsmasq installed successfully"
    fi
}

# Backup existing configuration
backup_config() {
    print_info "Backing up existing configuration..."

    local backup_dir="/etc/dnsmasq.backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    if [[ -f /etc/dnsmasq.conf ]]; then
        cp /etc/dnsmasq.conf "$backup_dir/"
        print_success "Backed up /etc/dnsmasq.conf"
    fi

    if [[ -d /etc/dnsmasq.d ]]; then
        cp -r /etc/dnsmasq.d "$backup_dir/" 2>/dev/null || true
        print_success "Backed up /etc/dnsmasq.d/"
    fi

    if [[ -f /etc/hosts.home ]]; then
        cp /etc/hosts.home "$backup_dir/"
        print_success "Backed up /etc/hosts.home"
    fi

    print_success "Backup saved to $backup_dir"
}

# Install configuration files
install_configs() {
    print_info "Installing configuration files..."

    # Create dnsmasq.d directory
    mkdir -p /etc/dnsmasq.d

    # Install main config
    cp dnsmasq.conf /etc/dnsmasq.conf
    print_success "Installed /etc/dnsmasq.conf"

    # Install domain config
    cp home-domain.conf /etc/dnsmasq.d/
    print_success "Installed /etc/dnsmasq.d/home-domain.conf"

    # Install hosts file
    cp hosts.home /etc/hosts.home
    print_success "Installed /etc/hosts.home"

    # Set proper permissions
    chmod 644 /etc/dnsmasq.conf
    chmod 644 /etc/dnsmasq.d/home-domain.conf
    chmod 644 /etc/hosts.home
}

# Handle systemd-resolved conflict
handle_systemd_resolved() {
    if systemctl is-active --quiet systemd-resolved; then
        print_warning "systemd-resolved is running and may conflict with dnsmasq"
        read -p "Disable systemd-resolved? (recommended) (y/N): " disable

        if [[ "$disable" == "y" || "$disable" == "Y" ]]; then
            print_info "Disabling systemd-resolved..."
            systemctl disable systemd-resolved
            systemctl stop systemd-resolved

            # Update resolv.conf
            rm -f /etc/resolv.conf
            echo "nameserver 127.0.0.1" > /etc/resolv.conf
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf

            print_success "systemd-resolved disabled"
        fi
    fi
}

# Test configuration
test_config() {
    print_info "Testing dnsmasq configuration..."

    if dnsmasq --test 2>&1; then
        print_success "Configuration is valid"
        return 0
    else
        print_error "Configuration has errors"
        return 1
    fi
}

# Restart dnsmasq
restart_dnsmasq() {
    print_info "Restarting dnsmasq service..."

    systemctl restart dnsmasq
    systemctl enable dnsmasq

    if systemctl is-active --quiet dnsmasq; then
        print_success "dnsmasq is running"
    else
        print_error "dnsmasq failed to start"
        journalctl -u dnsmasq -n 20 --no-pager
        return 1
    fi
}

# Test DNS resolution
test_dns() {
    print_info "Testing DNS resolution..."
    echo ""

    # Test wildcard resolution
    print_info "Testing: grafana.home"
    if nslookup grafana.home 127.0.0.1 2>/dev/null | grep -q "192.168.0.221"; then
        print_success "grafana.home → 192.168.0.221"
    else
        print_warning "grafana.home resolution failed"
    fi

    # Test another wildcard
    print_info "Testing: test.home"
    if nslookup test.home 127.0.0.1 2>/dev/null | grep -q "192.168.0.221"; then
        print_success "test.home → 192.168.0.221"
    else
        print_warning "test.home resolution failed"
    fi

    # Test external resolution
    print_info "Testing: google.com"
    if nslookup google.com 127.0.0.1 2>/dev/null | grep -q "Address"; then
        print_success "External DNS resolution working"
    else
        print_warning "External DNS resolution failed"
    fi

    echo ""
}

# Show summary
show_summary() {
    echo ""
    echo "=========================================="
    print_success "DNS Configuration Complete!"
    echo "=========================================="
    echo ""
    echo "DNS Server: 192.168.0.221 (this Pi 4)"
    echo "Domain: *.home → 192.168.0.221"
    echo ""
    echo "Configuration Files:"
    echo "  /etc/dnsmasq.conf"
    echo "  /etc/dnsmasq.d/home-domain.conf"
    echo "  /etc/hosts.home"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Configure this Pi 4 to use itself for DNS:"
    echo "   Edit /etc/dhcpcd.conf and add:"
    echo "   static domain_name_servers=127.0.0.1 8.8.8.8"
    echo ""
    echo "2. Configure your network clients:"
    echo "   - Router DHCP: Set DNS to 192.168.0.221"
    echo "   - Or set manually on each device"
    echo ""
    echo "3. Test DNS from any client:"
    echo "   nslookup grafana.home 192.168.0.221"
    echo ""
    echo "Example Service URLs (after nginx/K8s setup):"
    echo "  http://grafana.home"
    echo "  http://prometheus.home"
    echo "  http://minio.home"
    echo "  http://anyservice.home"
    echo ""
    echo "=========================================="
}

# Main function
main() {
    clear
    check_root
    show_config

    read -p "Continue with installation? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Installation cancelled"
        exit 0
    fi

    install_dnsmasq
    backup_config
    install_configs
    handle_systemd_resolved

    if test_config; then
        restart_dnsmasq
        test_dns
        show_summary
    else
        print_error "Configuration test failed. Please check the errors above."
        exit 1
    fi
}

main "$@"
