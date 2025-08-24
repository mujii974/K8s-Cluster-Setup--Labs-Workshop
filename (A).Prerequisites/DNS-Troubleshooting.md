# DNS Resolution Troubleshooting Guide

This guide addresses common DNS resolution issues in Kubernetes VM setups, particularly when VMs can ping the gateway but cannot reach external DNS servers.

## Problem Description

**Common Symptoms:**
- `/etc/resolv.conf` shows `nameserver 127.0.0.53` (systemd-resolved)
- `ip route` shows proper gateway (e.g., 192.168.10.1)
- Netplan configuration shows DNS servers 8.8.8.8 and 8.8.4.4 are configured
- VM can ping gateway but cannot reach external DNS servers like 8.8.8.8
- DNS resolution fails for domain names

**Root Cause:**
The issue typically occurs when systemd-resolved is not properly forwarding DNS queries to the configured external DNS servers, even though the network configuration appears correct.

## Quick Solution

Use the provided automated troubleshooting script:

```bash
# Navigate to the Prerequisites directory
cd "(A).Prerequisites"

# Make the script executable (if not already)
sudo chmod +x dns-troubleshoot.sh

# Run the full troubleshooting process
sudo ./dns-troubleshoot.sh
```

## Script Usage Options

The DNS troubleshooting script provides several modes of operation:

### Full Troubleshooting (Recommended)
```bash
sudo ./dns-troubleshoot.sh
# or
sudo ./dns-troubleshoot.sh --fix
```
This runs the complete diagnostic and repair process.

### Diagnosis Only
```bash
sudo ./dns-troubleshoot.sh --diagnose
```
Shows current DNS configuration without making changes.

### Test DNS Resolution
```bash
sudo ./dns-troubleshoot.sh --test
```
Tests connectivity and DNS resolution without making changes.

### Interactive Mode
```bash
sudo ./dns-troubleshoot.sh --interactive
```
Guides you through manual configuration options.

### Help
```bash
sudo ./dns-troubleshoot.sh --help
```
Shows all available options and usage examples.

## What the Script Does

The automated troubleshooting process performs the following steps:

1. **Diagnose Current State**
   - Shows current `/etc/resolv.conf` contents
   - Displays systemd-resolved status
   - Shows netplan configuration
   - Lists network routes and interfaces

2. **Test Network Connectivity**
   - Verifies gateway connectivity
   - Tests external IP reachability
   - Identifies connectivity vs. DNS issues

3. **Fix systemd-resolved**
   - Restarts systemd-resolved service
   - Reconfigures symbolic links
   - Enables proper service state

4. **Apply Network Configuration**
   - Regenerates netplan configuration
   - Applies network settings
   - Ensures DNS servers are properly configured

5. **Alternative DNS Configuration**
   - If systemd-resolved continues to fail
   - Creates direct `/etc/resolv.conf` configuration
   - Bypasses systemd-resolved entirely

6. **Comprehensive Testing**
   - Tests multiple DNS servers (8.8.8.8, 8.8.4.4, 1.1.1.1)
   - Tests multiple domains (google.com, kubernetes.io, github.com)
   - Provides detailed success/failure reporting

## Manual Troubleshooting Steps

If you prefer manual troubleshooting or need to understand the process:

### 1. Check Current DNS Configuration
```bash
# Check resolv.conf
cat /etc/resolv.conf

# Check systemd-resolved status
sudo systemctl status systemd-resolved
sudo resolvectl status

# Check netplan configuration
sudo find /etc/netplan -name "*.yaml" -exec cat {} \;
```

### 2. Test Basic Connectivity
```bash
# Test gateway connectivity
ping -c 3 $(ip route | grep default | awk '{print $3}')

# Test external DNS server connectivity
ping -c 3 8.8.8.8
```

### 3. Test DNS Resolution
```bash
# Test with different DNS servers
nslookup google.com 8.8.8.8
nslookup google.com 8.8.4.4
dig @8.8.8.8 google.com
```

### 4. Fix systemd-resolved
```bash
# Restart systemd-resolved
sudo systemctl stop systemd-resolved
sudo systemctl start systemd-resolved
sudo systemctl enable systemd-resolved

# Recreate symlink
sudo rm /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Apply netplan
sudo netplan generate
sudo netplan apply

# Flush DNS cache
sudo resolvectl flush-caches
```

### 5. Alternative: Direct DNS Configuration
If systemd-resolved continues to cause issues:

```bash
# Backup current configuration
sudo cp /etc/resolv.conf /etc/resolv.conf.backup

# Create direct DNS configuration
sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
search localdomain
EOF

# Make immutable to prevent overwriting
sudo chattr +i /etc/resolv.conf
```

## Troubleshooting Network Configuration

If DNS issues persist, check your netplan configuration:

### Example Working Netplan Configuration
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:  # Replace with your interface name
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.100.10/24  # Your static IP
      gateway4: 192.168.100.1  # Your gateway
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
          - 1.1.1.1
        search:
          - localdomain
```

Apply the configuration:
```bash
sudo netplan generate
sudo netplan apply
```

## Common Issues and Solutions

### Issue: DNS works intermittently
**Solution:** Flush DNS cache and restart networking
```bash
sudo resolvectl flush-caches
sudo systemctl restart systemd-networkd
sudo systemctl restart systemd-resolved
```

### Issue: Changes don't persist after reboot
**Solution:** Ensure netplan configuration is saved and cloud-init is disabled
```bash
# Disable cloud-init network configuration
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null <<EOF
network: {config: disabled}
EOF
```

### Issue: Corporate firewall blocking DNS
**Solution:** Use alternative DNS servers or configure corporate DNS
```bash
# Try corporate or local DNS servers
# Update netplan with your organization's DNS servers
```

### Issue: systemd-resolved conflicts
**Solution:** Disable systemd-resolved and use direct configuration
```bash
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
# Use direct /etc/resolv.conf configuration
```

## Verification

After applying fixes, verify DNS is working:

```bash
# Test DNS resolution
nslookup google.com
dig kubernetes.io
ping -c 3 google.com

# Test Kubernetes-specific DNS
nslookup registry.k8s.io
```

## Integration with Kubernetes Setup

Proper DNS resolution is critical for:
- Downloading Kubernetes packages
- Pulling container images
- Cluster communication
- Pod DNS resolution

Ensure DNS is working before proceeding with Kubernetes installation steps.

## Getting Help

If DNS issues persist after trying these solutions:

1. Check with your network administrator
2. Verify firewall settings: `sudo ufw status`
3. Check virtualization platform network settings
4. Review network hardware configuration
5. Consider using the interactive mode of the troubleshooting script for guided assistance

For additional support, refer to the main networking documentation in `2.Networking.md`.