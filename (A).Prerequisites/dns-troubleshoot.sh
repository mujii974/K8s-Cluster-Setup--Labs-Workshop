#!/bin/bash

# DNS Troubleshooting Script for Kubernetes VM Setup
# Fixes issues where VMs can ping gateway but cannot reach external DNS servers
# Author: K8s Workshop Guide
# Usage: sudo ./dns-troubleshoot.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo ./dns-troubleshoot.sh"
        exit 1
    fi
}

# Function to test DNS resolution
test_dns() {
    local dns_server=$1
    local test_domain=$2
    
    log "Testing DNS resolution for $test_domain using $dns_server..."
    
    if nslookup $test_domain $dns_server >/dev/null 2>&1; then
        success "DNS resolution successful for $test_domain via $dns_server"
        return 0
    else
        error "DNS resolution failed for $test_domain via $dns_server"
        return 1
    fi
}

# Function to test network connectivity
test_connectivity() {
    log "Testing network connectivity..."
    
    # Test gateway connectivity
    gateway=$(ip route | grep default | awk '{print $3}' | head -n1)
    if [ -n "$gateway" ]; then
        log "Testing connectivity to gateway: $gateway"
        if ping -c 3 $gateway >/dev/null 2>&1; then
            success "Gateway ($gateway) is reachable"
        else
            error "Cannot reach gateway ($gateway)"
            return 1
        fi
    else
        error "No default gateway found"
        return 1
    fi
    
    # Test external IP connectivity (Google DNS)
    log "Testing connectivity to external DNS server (8.8.8.8)..."
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        success "External DNS server (8.8.8.8) is reachable"
        return 0
    else
        error "Cannot reach external DNS server (8.8.8.8)"
        return 1
    fi
}

# Function to diagnose current DNS configuration
diagnose_dns() {
    log "Diagnosing current DNS configuration..."
    
    echo
    log "Current /etc/resolv.conf contents:"
    cat /etc/resolv.conf
    
    echo
    log "Current systemd-resolved status:"
    systemctl status systemd-resolved --no-pager || true
    
    echo
    log "Current resolved configuration:"
    resolvectl status || true
    
    echo
    log "Current netplan configuration:"
    find /etc/netplan -name "*.yaml" -exec echo "=== {} ===" \; -exec cat {} \;
    
    echo
    log "Current network routes:"
    ip route
    
    echo
    log "Current network interfaces:"
    ip addr show
}

# Function to restart and reconfigure systemd-resolved
fix_systemd_resolved() {
    log "Restarting and reconfiguring systemd-resolved..."
    
    # Stop systemd-resolved
    systemctl stop systemd-resolved
    
    # Remove existing resolv.conf if it's a symlink
    if [ -L /etc/resolv.conf ]; then
        rm /etc/resolv.conf
    fi
    
    # Restart systemd-resolved
    systemctl start systemd-resolved
    systemctl enable systemd-resolved
    
    # Recreate symlink
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    
    success "systemd-resolved restarted and reconfigured"
}

# Function to apply netplan configuration
apply_netplan() {
    log "Applying netplan configuration..."
    
    # Generate and apply netplan
    netplan generate
    netplan apply
    
    success "Netplan configuration applied"
}

# Function to flush DNS cache
flush_dns_cache() {
    log "Flushing DNS cache..."
    
    # Flush systemd-resolved cache
    resolvectl flush-caches || true
    
    success "DNS cache flushed"
}

# Function to configure alternative DNS method (direct resolv.conf)
configure_direct_dns() {
    warning "Attempting alternative DNS configuration (direct /etc/resolv.conf)..."
    
    # Backup current resolv.conf
    cp /etc/resolv.conf /etc/resolv.conf.backup
    
    # Create new resolv.conf with direct DNS servers
    cat > /etc/resolv.conf << EOF
# DNS configuration for Kubernetes cluster
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
search localdomain
EOF
    
    # Make it immutable to prevent systemd from overwriting
    chattr +i /etc/resolv.conf
    
    success "Direct DNS configuration applied"
    log "Note: /etc/resolv.conf is now immutable. To modify, run: chattr -i /etc/resolv.conf"
}

# Function to create/update netplan configuration with proper DNS
create_netplan_config() {
    local interface=$1
    local ip_address=$2
    local gateway=$3
    
    log "Creating/updating netplan configuration..."
    
    # Find the existing netplan file or create a new one
    netplan_file="/etc/netplan/01-netcfg.yaml"
    if [ -f "/etc/netplan/50-cloud-init.yaml" ]; then
        netplan_file="/etc/netplan/50-cloud-init.yaml"
    fi
    
    # Backup existing configuration
    if [ -f "$netplan_file" ]; then
        cp "$netplan_file" "${netplan_file}.backup"
    fi
    
    # Create netplan configuration
    cat > "$netplan_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: false
      dhcp6: false
      addresses:
        - $ip_address
      gateway4: $gateway
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
          - 1.1.1.1
        search:
          - localdomain
EOF
    
    success "Netplan configuration created/updated in $netplan_file"
}

# Function to run comprehensive DNS tests
run_dns_tests() {
    log "Running comprehensive DNS tests..."
    
    # Test various DNS servers and domains
    local dns_servers=("8.8.8.8" "8.8.4.4" "1.1.1.1")
    local test_domains=("google.com" "kubernetes.io" "github.com")
    local success_count=0
    local total_tests=0
    
    for dns_server in "${dns_servers[@]}"; do
        for domain in "${test_domains[@]}"; do
            ((total_tests++))
            if test_dns "$dns_server" "$domain"; then
                ((success_count++))
            fi
        done
    done
    
    echo
    log "DNS Test Results: $success_count/$total_tests tests passed"
    
    if [ $success_count -eq $total_tests ]; then
        success "All DNS tests passed!"
        return 0
    elif [ $success_count -gt 0 ]; then
        warning "Some DNS tests passed ($success_count/$total_tests)"
        return 1
    else
        error "All DNS tests failed"
        return 2
    fi
}

# Interactive mode function
interactive_mode() {
    log "Starting interactive DNS troubleshooting..."
    
    # Get network interface
    echo
    log "Available network interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | grep -v lo
    
    read -p "Enter the network interface name (e.g., eth0, ens33): " interface
    
    # Get current IP and gateway
    current_ip=$(ip addr show $interface | grep "inet " | awk '{print $2}' | head -n1)
    current_gateway=$(ip route | grep default | awk '{print $3}' | head -n1)
    
    echo
    log "Current IP: $current_ip"
    log "Current Gateway: $current_gateway"
    
    read -p "Do you want to update the netplan configuration? (y/n): " update_netplan
    
    if [[ $update_netplan =~ ^[Yy]$ ]]; then
        if [ -n "$current_ip" ] && [ -n "$current_gateway" ]; then
            create_netplan_config "$interface" "$current_ip" "$current_gateway"
        else
            read -p "Enter IP address (e.g., 192.168.100.10/24): " ip_address
            read -p "Enter gateway IP (e.g., 192.168.100.1): " gateway_ip
            create_netplan_config "$interface" "$ip_address" "$gateway_ip"
        fi
    fi
}

# Main troubleshooting function
main_troubleshoot() {
    log "Starting DNS troubleshooting process..."
    
    # Step 1: Diagnose current state
    diagnose_dns
    
    # Step 2: Test current connectivity
    if ! test_connectivity; then
        error "Basic network connectivity failed. Check network configuration first."
        return 1
    fi
    
    # Step 3: Test current DNS
    if run_dns_tests; then
        success "DNS is working correctly. No fixes needed."
        return 0
    fi
    
    # Step 4: Try fixing systemd-resolved
    log "Attempting to fix systemd-resolved..."
    fix_systemd_resolved
    sleep 2
    
    # Step 5: Apply netplan configuration
    apply_netplan
    sleep 2
    
    # Step 6: Flush DNS cache
    flush_dns_cache
    sleep 2
    
    # Step 7: Test DNS again
    log "Testing DNS after systemd-resolved fix..."
    if run_dns_tests; then
        success "DNS issues resolved with systemd-resolved fix!"
        return 0
    fi
    
    # Step 8: Try alternative DNS configuration
    warning "systemd-resolved fix didn't work. Trying alternative DNS configuration..."
    configure_direct_dns
    sleep 2
    
    # Step 9: Final DNS test
    log "Testing DNS after alternative configuration..."
    if run_dns_tests; then
        success "DNS issues resolved with alternative configuration!"
        log "Your system is now using direct DNS configuration instead of systemd-resolved."
        return 0
    else
        error "DNS issues persist. Manual intervention may be required."
        log "Suggestions:"
        log "1. Check firewall settings: sudo ufw status"
        log "2. Check if DNS ports are blocked"
        log "3. Verify network hardware/virtualization settings"
        log "4. Check with network administrator"
        return 1
    fi
}

# Display usage information
show_usage() {
    echo "DNS Troubleshooting Script for Kubernetes VM Setup"
    echo
    echo "Usage: sudo $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -d, --diagnose  Only run diagnosis (no fixes)"
    echo "  -t, --test      Only run DNS tests"
    echo "  -i, --interactive  Run in interactive mode"
    echo "  -f, --fix       Run full troubleshooting and fix process"
    echo
    echo "Examples:"
    echo "  sudo $0 --diagnose    # Only diagnose current DNS setup"
    echo "  sudo $0 --test        # Only test DNS resolution"
    echo "  sudo $0 --fix         # Run full troubleshooting process"
    echo "  sudo $0 --interactive # Interactive configuration"
}

# Main script logic
main() {
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--diagnose)
            check_root
            diagnose_dns
            ;;
        -t|--test)
            check_root
            test_connectivity
            run_dns_tests
            ;;
        -i|--interactive)
            check_root
            interactive_mode
            main_troubleshoot
            ;;
        -f|--fix|"")
            check_root
            main_troubleshoot
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"