#!/bin/bash

# Universal Forwarder Complete Uninstall Script
set -e

echo "=== Universal Forwarder Uninstall Script ==="
echo "This script will completely remove the Universal Forwarder installation"
echo

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

error() {
    echo -e "${RED}ERROR:${NC} $1"
}

success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

# Confirmation prompt
echo "This will remove:"
echo "  • Universal Forwarder service"
echo "  • /opt/splunkforwarder directory and all data"
echo "  • Systemd service files"
echo "  • Downloaded installation files"
echo "  • Environment variables from ~/.bashrc"
echo

read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo
log "Starting Universal Forwarder uninstall..."

# 1. Stop and disable systemd services
echo "1. Stopping and disabling services..."
echo "-----------------------------------"

# Stop splunkforwarder service
if systemctl is-active --quiet splunkforwarder 2>/dev/null; then
    log "Stopping splunkforwarder service..."
    sudo systemctl stop splunkforwarder
    success "Service stopped"
else
    log "splunkforwarder service was not running"
fi

# Disable service
if systemctl is-enabled --quiet splunkforwarder 2>/dev/null; then
    log "Disabling splunkforwarder service..."
    sudo systemctl disable splunkforwarder
    success "Service disabled"
else
    log "splunkforwarder service was not enabled"
fi

# 2. Stop Universal Forwarder process directly
echo
echo "2. Stopping Universal Forwarder processes..."
echo "--------------------------------------------"

if [ -x /opt/splunkforwarder/bin/splunk ]; then
    log "Stopping splunkd via splunk command..."
    sudo -u splunk /opt/splunkforwarder/bin/splunk stop 2>/dev/null || log "Already stopped or failed to stop gracefully"
fi

# Kill any remaining splunk processes
log "Checking for remaining splunk processes..."
splunk_pids=$(pgrep -f splunkforwarder 2>/dev/null || true)
if [ -n "$splunk_pids" ]; then
    log "Killing remaining splunk processes: $splunk_pids"
    sudo kill -TERM $splunk_pids 2>/dev/null || true
    sleep 5
    # Force kill if still running
    splunk_pids=$(pgrep -f splunkforwarder 2>/dev/null || true)
    if [ -n "$splunk_pids" ]; then
        log "Force killing stubborn processes: $splunk_pids"
        sudo kill -KILL $splunk_pids 2>/dev/null || true
    fi
fi

success "All Universal Forwarder processes stopped"

# 3. Remove systemd service files
echo
echo "3. Removing systemd service files..."
echo "-----------------------------------"

service_files=(
    "/etc/systemd/system/splunkforwarder.service"
    "/etc/systemd/system/multi-user.target.wants/splunkforwarder.service"
)

for service_file in "${service_files[@]}"; do
    if [ -f "$service_file" ]; then
        log "Removing $service_file"
        sudo rm -f "$service_file"
        success "Removed $service_file"
    else
        log "$service_file does not exist"
    fi
done

# Reload systemd
log "Reloading systemd daemon..."
sudo systemctl daemon-reload
success "Systemd daemon reloaded"

# 4. Remove Universal Forwarder installation directory
echo
echo "4. Removing installation directory..."
echo "------------------------------------"

if [ -d /opt/splunkforwarder ]; then
    log "Removing /opt/splunkforwarder directory..."
    sudo rm -rf /opt/splunkforwarder
    success "Installation directory removed"
else
    log "/opt/splunkforwarder directory does not exist"
fi

# 5. Remove downloaded installation files
echo
echo "5. Cleaning up downloaded files..."
echo "---------------------------------"

download_files=(
    "/tmp/splunkforwarder-*.tgz"
    "/tmp/splunkforwarder-*.tar.gz"
)

for pattern in "${download_files[@]}"; do
    files=$(ls $pattern 2>/dev/null || true)
    if [ -n "$files" ]; then
        log "Removing downloaded files: $files"
        sudo rm -f $files
        success "Downloaded files removed"
    else
        log "No downloaded files found matching $pattern"
    fi
done

# 6. Remove environment variables from ~/.bashrc
echo
echo "6. Cleaning up environment variables..."
echo "--------------------------------------"

bashrc_file="$HOME/.bashrc"
if [ -f "$bashrc_file" ]; then
    # Create backup
    cp "$bashrc_file" "${bashrc_file}.backup.$(date +%s)"
    log "Created backup: ${bashrc_file}.backup.$(date +%s)"
    
    # Remove Splunk environment variables
    log "Removing Splunk environment variables from ~/.bashrc..."
    sed -i '/export SPLUNK_HOME=\/opt\/splunkforwarder/d' "$bashrc_file"
    sed -i '/export PATH=.*splunkforwarder/d' "$bashrc_file"
    sed -i '/SPLUNK_HOME.*splunkforwarder/d' "$bashrc_file"
    
    success "Environment variables removed from ~/.bashrc"
else
    log "~/.bashrc file not found"
fi

# 7. Remove splunk user (optional)
echo
echo "7. User account cleanup..."
echo "-------------------------"

if id "splunk" &>/dev/null; then
    read -p "Remove splunk user account? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Removing splunk user account..."
        sudo userdel -r splunk 2>/dev/null || {
            warning "Failed to remove user with home directory, trying without -r flag"
            sudo userdel splunk 2>/dev/null || warning "Failed to remove splunk user"
        }
        success "Splunk user account removed"
    else
        log "Keeping splunk user account"
    fi
else
    log "Splunk user does not exist"
fi

# 8. Clean up any remaining configuration files
echo
echo "8. Final cleanup..."
echo "------------------"

# Remove any remaining splunk-related files
remaining_files=(
    "/var/log/splunk*"
    "/etc/init.d/splunk*"
    "/home/splunk"
)

for pattern in "${remaining_files[@]}"; do
    files=$(ls -d $pattern 2>/dev/null || true)
    if [ -n "$files" ]; then
        read -p "Remove remaining files ($files)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf $files
            success "Removed $files"
        fi
    fi
done

# 9. Verification
echo
echo "9. Verification..."
echo "-----------------"

log "Verifying removal..."

# Check if service exists
if systemctl list-unit-files | grep -q splunkforwarder; then
    warning "Systemd service still exists"
else
    success "Systemd service removed"
fi

# Check if directory exists
if [ -d /opt/splunkforwarder ]; then
    warning "Installation directory still exists"
else
    success "Installation directory removed"
fi

# Check if processes are running
if pgrep -f splunkforwarder >/dev/null 2>&1; then
    warning "Splunk processes still running"
else
    success "No splunk processes running"
fi

# Check if user exists
if id "splunk" &>/dev/null; then
    log "Splunk user still exists (kept by choice or removal failed)"
else
    success "Splunk user removed"
fi
success "Universal Forwarder uninstall completed successfully!"