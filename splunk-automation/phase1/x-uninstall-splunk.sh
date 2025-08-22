#!/bin/bash

# Splunk Enterprise Uninstall Script for Ubuntu
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/phase1-uninstall.log"

# Create logs directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    error "$1"
    exit 1
}

echo "=== Splunk Enterprise Uninstall Script ==="
echo "This script will completely remove Splunk Enterprise installation"
echo

log "Starting Splunk Enterprise uninstall..."

# Confirmation prompt
echo "This will remove:"
echo "  • Splunk Enterprise service and processes"
echo "  • /opt/splunk directory and ALL data/configurations"
echo "  • Splunk package from system"
echo "  • Systemd service files"
echo "  • Downloaded .deb files"
echo "  • Environment variables from ~/.bashrc"
echo "  • All indexes, apps, and custom configurations"
echo
warning "This action is IRREVERSIBLE - all Splunk data will be lost!"
echo

read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Uninstall cancelled by user"
    exit 0
fi

echo
log "Proceeding with Splunk Enterprise uninstall..."

# 1. Stop and disable systemd service
echo "1. Stopping and disabling Splunk service..."
echo "-------------------------------------------"

if systemctl is-active --quiet splunk 2>/dev/null; then
    log "Stopping splunk service..."
    sudo systemctl stop splunk
    success "Splunk service stopped"
else
    log "Splunk service was not running"
fi

if systemctl is-enabled --quiet splunk 2>/dev/null; then
    log "Disabling splunk service..."
    sudo systemctl disable splunk
    success "Splunk service disabled"
else
    log "Splunk service was not enabled"
fi

# 2. Stop Splunk processes directly
echo
echo "2. Stopping Splunk processes..."
echo "-------------------------------"

if [ -x /opt/splunk/bin/splunk ]; then
    log "Stopping splunkd via splunk command..."
    sudo -u splunk /opt/splunk/bin/splunk stop 2>/dev/null || log "Already stopped or failed to stop gracefully"
    success "Splunk stopped via command"
else
    log "Splunk binary not found, skipping graceful stop"
fi

# Kill any remaining splunk processes
log "Checking for remaining splunk processes..."
splunk_pids=$(pgrep -f "/opt/splunk" 2>/dev/null || true)
if [ -n "$splunk_pids" ]; then
    log "Killing remaining splunk processes: $splunk_pids"
    sudo kill -TERM $splunk_pids 2>/dev/null || true
    sleep 5
    
    # Force kill if still running
    splunk_pids=$(pgrep -f "/opt/splunk" 2>/dev/null || true)
    if [ -n "$splunk_pids" ]; then
        log "Force killing stubborn processes: $splunk_pids"
        sudo kill -KILL $splunk_pids 2>/dev/null || true
    fi
    success "All Splunk processes terminated"
else
    log "No Splunk processes found running"
fi

# 3. Remove systemd service files
echo
echo "3. Removing systemd service files..."
echo "-----------------------------------"

service_files=(
    "/etc/systemd/system/splunk.service"
    "/etc/systemd/system/multi-user.target.wants/splunk.service"
    "/lib/systemd/system/Splunkd.service"
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

# 4. Uninstall Splunk package
echo
echo "4. Uninstalling Splunk package..."
echo "---------------------------------"

# Check if Splunk package is installed
if dpkg -l | grep -q "^ii.*splunk"; then
    package_name=$(dpkg -l | grep "^ii.*splunk" | awk '{print $2}' | head -1)
    log "Found installed Splunk package: $package_name"
    
    log "Removing Splunk package..."
    sudo dpkg --remove "$package_name" || {
        warning "Failed to remove package cleanly, trying purge..."
        sudo dpkg --purge "$package_name" || warning "Package removal had issues, continuing..."
    }
    success "Splunk package removed"
else
    log "No Splunk package found in dpkg database"
fi

# 5. Remove installation directory
echo
echo "5. Removing Splunk installation directory..."
echo "-------------------------------------------"

if [ -d /opt/splunk ]; then
    log "Removing /opt/splunk directory..."
    warning "This will delete ALL Splunk data, configurations, and indexes"
    
    # List what's in the directory
    log "Directory contents:"
    sudo ls -la /opt/splunk/ | head -10 | while read line; do log "  $line"; done
    
    sudo rm -rf /opt/splunk
    success "Splunk installation directory removed"
else
    log "/opt/splunk directory does not exist"
fi

# 6. Remove downloaded installation files
echo
echo "6. Cleaning up downloaded files..."
echo "---------------------------------"

download_patterns=(
    "/tmp/splunk-*.deb"
    "/tmp/splunk-*-linux-*.deb"
    "splunk-*.deb"
)

for pattern in "${download_patterns[@]}"; do
    files=$(ls $pattern 2>/dev/null || true)
    if [ -n "$files" ]; then
        log "Removing downloaded files: $files"
        sudo rm -f $files
        success "Downloaded files removed"
    else
        log "No downloaded files found matching $pattern"
    fi
done

# Also check current directory
if ls splunk-*.deb 1> /dev/null 2>&1; then
    log "Found Splunk .deb files in current directory"
    read -p "Remove Splunk .deb files from current directory? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f splunk-*.deb
        success "Local .deb files removed"
    fi
fi

# 7. Remove environment variables from ~/.bashrc
echo
echo "7. Cleaning up environment variables..."
echo "--------------------------------------"

bashrc_file="$HOME/.bashrc"
if [ -f "$bashrc_file" ]; then
    # Create backup
    backup_file="${bashrc_file}.backup.$(date +%s)"
    cp "$bashrc_file" "$backup_file"
    log "Created backup: $backup_file"
    
    # Remove Splunk environment variables
    log "Removing Splunk environment variables from ~/.bashrc..."
    sed -i '/export SPLUNK_HOME=\/opt\/splunk/d' "$bashrc_file"
    sed -i '/export PATH=.*\/opt\/splunk/d' "$bashrc_file"
    sed -i '/SPLUNK_HOME.*\/opt\/splunk/d' "$bashrc_file"
    
    success "Environment variables removed from ~/.bashrc"
    log "Backup saved as: $backup_file"
else
    log "~/.bashrc file not found"
fi

# 8. Clean package cache
echo
echo "8. Cleaning package cache..."
echo "---------------------------"

log "Cleaning apt package cache..."
sudo apt-get clean
sudo apt-get autoremove -y
success "Package cache cleaned"

# 9. Remove splunk user (optional)
echo
echo "9. User account cleanup..."
echo "-------------------------"

if id "splunk" &>/dev/null; then
    echo "The 'splunk' user account still exists."
    read -p "Remove splunk user account and home directory? (y/N): " -n 1 -r
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

# 10. Final cleanup
echo
echo "10. Final cleanup..."
echo "-------------------"

# Remove any remaining splunk-related files
remaining_locations=(
    "/var/log/splunk*"
    "/etc/init.d/splunk*"
    "/home/splunk"
    "/var/lib/dpkg/info/splunk*"
)

for pattern in "${remaining_locations[@]}"; do
    files=$(ls -d $pattern 2>/dev/null || true)
    if [ -n "$files" ]; then
        log "Found remaining files: $files"
        read -p "Remove these files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf $files
            success "Removed $files"
        fi
    fi
done

# 11. Verification
echo
echo "11. Verification..."
echo "------------------"

log "Verifying complete removal..."

# Check if service exists
if systemctl list-unit-files | grep -q splunk; then
    warning "Systemd service references still exist"
else
    success "No systemd service references found"
fi

# Check if directory exists
if [ -d /opt/splunk ]; then
    warning "Installation directory still exists"
else
    success "Installation directory completely removed"
fi

# Check if processes are running
if pgrep -f "/opt/splunk" >/dev/null 2>&1; then
    warning "Splunk processes still running"
else
    success "No Splunk processes running"
fi

# Check if package is removed
if dpkg -l | grep -q splunk; then
    warning "Splunk package may still be installed"
else
    success "Splunk package completely removed"
fi

# Check if user exists
if id "splunk" &>/dev/null; then
    log "Splunk user still exists (kept by choice or removal failed)"
else
    success "Splunk user removed"
fi

# 12. Port verification
echo
echo "12. Port verification..."
echo "-----------------------"

# Check if Splunk ports are still in use
splunk_ports=(8000 8089 9997 8191)
port_issues=false

for port in "${splunk_ports[@]}"; do
    if netstat -tln 2>/dev/null | grep -q ":$port " || ss -tln 2>/dev/null | grep -q ":$port "; then
        warning "Port $port is still in use"
        port_issues=true
    else
        log "Port $port is free"
    fi
done

if [ "$port_issues" = false ]; then
    success "All Splunk ports are free"
fi

# Summary
echo
echo "============================================"
echo "           UNINSTALL COMPLETE"
echo "============================================"

success "Splunk Enterprise has been completely uninstalled"
echo
echo "What was removed:"
echo "✓ Splunk Enterprise service and processes"
echo "✓ Splunk package (via dpkg)"
echo "✓ Installation directory (/opt/splunk)"
echo "✓ All indexes, configurations, and data"
echo "✓ Systemd service files"
echo "✓ Downloaded .deb installation files"
echo "✓ Environment variables from ~/.bashrc"

if ! id "splunk" &>/dev/null; then
    echo "✓ Splunk user account"
else
    echo "• Splunk user account (kept by choice)"
fi

echo
echo "Manual steps (recommended):"
echo "• Reload your shell environment: source ~/.bashrc"
echo "• Restart your system to ensure all changes take effect"
echo "• Review system logs for any remaining references"
echo
echo "Logs saved to: $LOG_FILE"

log "Splunk Enterprise uninstall completed successfully"

echo
echo "System is now clean of Splunk Enterprise installation."