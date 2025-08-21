#!/bin/bash

# Splunk Enterprise Installation Script for Ubuntu
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/phase1-install.log"
SPLUNK_VERSION="8.2.6"
SPLUNK_BUILD="a6fe1ee8894b"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting Splunk Enterprise installation..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error_exit "This script should not be run as root"
fi

# Create directories
sudo mkdir -p /opt/splunk
sudo chown splunk:splunk /opt/splunk

# Download Splunk Enterprise
log "Downloading Splunk Enterprise..."
cd /tmp
wget -O "splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-2.6-amd64.deb" \
    "https://download.splunk.com/products/splunk/releases/${SPLUNK_VERSION}/linux/splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-2.6-amd64.deb" \
    || error_exit "Failed to download Splunk"

# Install Splunk
log "Installing Splunk..."
sudo dpkg -i "splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-2.6-amd64.deb" \
    || error_exit "Failed to install Splunk"

# Set ownership
sudo chown -R splunk:splunk /opt/splunk

# Configure environment
echo 'export SPLUNK_HOME=/opt/splunk' >> ~/.bashrc
echo 'export PATH=$SPLUNK_HOME/bin:$PATH' >> ~/.bashrc
export SPLUNK_HOME=/opt/splunk
export PATH=$SPLUNK_HOME/bin:$PATH

# Start Splunk and accept license
log "Starting Splunk for first time..."
sudo -u splunk $SPLUNK_HOME/bin/splunk start --accept-license --answer-yes --no-prompt \
    --seed-passwd changeme || error_exit "Failed to start Splunk"

# Enable boot start
log "Enabling boot start..."
sudo $SPLUNK_HOME/bin/splunk enable boot-start -user splunk --accept-license \
    || error_exit "Failed to enable boot start"

# Create systemd service (for WSL-2 compatibility)
sudo tee /etc/systemd/system/splunk.service > /dev/null <<EOF
[Unit]
Description=Splunk Enterprise
After=network.target

[Service]
Type=forking
User=splunk
Group=splunk
ExecStart=/opt/splunk/bin/splunk start
ExecStop=/opt/splunk/bin/splunk stop
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable splunk

log "Splunk installation completed successfully"
log "Access Splunk Web at: http://localhost:8000"
log "Default credentials: admin/changeme"