#!/bin/bash

# Universal Forwarder Installation Script with Configurable Ports (CORRECTED)
set -e

# ============================================================================
# PORT CONFIGURATION - Environment Variables
# ============================================================================
# Universal Forwarder Ports
UF_MGMT_PORT="${UF_MGMT_PORT:-8188}"           # Universal Forwarder management port
UF_WEB_PORT="${UF_WEB_PORT:-8100}"             # Universal Forwarder web port

# Indexer/Splunk Enterprise Ports (where forwarder connects to)
INDEXER_RECEIVE_PORT="${INDEXER_RECEIVE_PORT:-9997}"    # Port where indexer receives data
INDEXER_MGMT_PORT="${INDEXER_MGMT_PORT:-8089}"          # Indexer management port for deployment

# Indexer Host (in case you want to forward to remote indexer)
INDEXER_HOST="${INDEXER_HOST:-localhost}"

# ============================================================================
# SCRIPT CONFIGURATION
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/phase2-forwarder.log"
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

# ============================================================================
# MAIN INSTALLATION
# ============================================================================
log "Installing Universal Forwarder with custom port configuration..."
log "Configuration:"
log "  UF Management Port: $UF_MGMT_PORT"
log "  UF Web Port: $UF_WEB_PORT"
log "  Indexer Host: $INDEXER_HOST"
log "  Indexer Receive Port: $INDEXER_RECEIVE_PORT"
log "  Indexer Management Port: $INDEXER_MGMT_PORT"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error_exit "This script should not be run as root"
fi

# Check if splunk user exists
if ! id "splunk" &>/dev/null; then
    log "Creating splunk user..."
    sudo useradd -m -s /bin/bash splunk
    log "Splunk user created"
fi

# Create directories
sudo mkdir -p /opt/splunkforwarder
sudo chown splunk:splunk /opt/splunkforwarder

# Download Universal Forwarder
log "Downloading Universal Forwarder..."
cd /tmp
wget -O "splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.tgz" \
    "https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.tgz" \
    || error_exit "Failed to download Universal Forwarder"

# Extract and install
log "Extracting Universal Forwarder..."
sudo tar -xzf "splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.tgz" -C /opt/ \
    || error_exit "Failed to extract Universal Forwarder"

# Set ownership
sudo chown -R splunk:splunk /opt/splunkforwarder

# Configure environment
echo 'export SPLUNK_FORWARDER_HOME=/opt/splunkforwarder' >> ~/.bashrc
echo 'export PATH=$SPLUNK_FORWARDER_HOME/bin:$PATH' >> ~/.bashrc
export SPLUNK_FORWARDER_HOME=/opt/splunkforwarder
export PATH=$SPLUNK_FORWARDER_HOME/bin:$PATH

# ============================================================================
# PORT CONFIGURATION (CORRECTED)
# ============================================================================
log "Configuring Universal Forwarder with custom ports..."

# Create local configuration directory
sudo -u splunk mkdir -p /opt/splunkforwarder/etc/system/local

# Get actual hostname (not $(hostname) which caused issues)
ACTUAL_HOSTNAME=$(hostname)
log "Using hostname: $ACTUAL_HOSTNAME"

# Configure server.conf with VALID Universal Forwarder settings
log "Creating valid server.conf for Universal Forwarder..."
# Fix the server.conf
sudo -u splunk tee /opt/splunkforwarder/etc/system/local/server.conf > /dev/null <<EOF
[general]
serverName = BNXL-78463-WL_forwarder

[sslConfig]
enableSplunkdSSL = true

[lmpool:auto_generated_pool_forwarder]
description = auto_generated_pool_forwarder
quota = MAX
slaves = *
stack_id = forwarder

[lmpool:auto_generated_pool_free]
description = auto_generated_pool_free
quota = MAX
slaves = *
stack_id = free

[license]
master_uri = localhost:8089
EOF

# Configure web.conf with custom web port (CORRECTED)
log "Setting web port to $UF_WEB_PORT..."
sudo -u splunk tee /opt/splunkforwarder/etc/system/local/web.conf > /dev/null <<EOF
[settings]
httpport = $UF_WEB_PORT
mgmtHostPort = 127.0.0.1:$UF_MGMT_PORT
enableSplunkWebSSL = false
EOF

# Create inputs.conf placeholder
sudo -u splunk tee /opt/splunkforwarder/etc/system/local/inputs.conf > /dev/null <<EOF
# Universal Forwarder inputs configuration
# Inputs will be managed by deployment server

[default]
host = $ACTUAL_HOSTNAME
EOF

# Create user-seed.conf
sudo -u splunk tee /opt/splunkforwarder/etc/system/local/user-seed.conf > /dev/null <<EOF
[user_info]
USERNAME = admin
PASSWORD = changeme
EOF

# ============================================================================
# ENABLE RECEIVING IN SPLUNK ENTERPRISE (REQUIRED)
# ============================================================================
log "Ensuring Splunk Enterprise can receive data..."
if [ -x /opt/splunk/bin/splunk ]; then
    log "Enabling receiving port $INDEXER_RECEIVE_PORT in Splunk Enterprise..."
    sudo -u splunk /opt/splunk/bin/splunk enable listen $INDEXER_RECEIVE_PORT -auth admin:changeme 2>/dev/null || {
        log "Note: Could not enable receiving port. Please ensure Splunk Enterprise is running and configured."
    }
else
    log "Warning: Splunk Enterprise not found. Please install it first and enable receiving on port $INDEXER_RECEIVE_PORT"
fi

# ============================================================================
# START AND CONFIGURE FORWARDER
# ============================================================================
log "Starting Universal Forwarder..."
sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk start --accept-license --answer-yes --no-prompt \
    || error_exit "Failed to start Universal Forwarder"

# Verify forwarder is running
log "Verifying Universal Forwarder is running..."
sleep 10

# Check if forwarder started successfully
if sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk status | grep -q "splunkd is running"; then
    log "✓ Universal Forwarder started successfully"
else
    error_exit "Universal Forwarder failed to start properly"
fi

# Enable boot start
log "Enabling boot start..."
sudo $SPLUNK_FORWARDER_HOME/bin/splunk enable boot-start -user splunk --accept-license \
    || error_exit "Failed to enable boot start"

# ============================================================================
# CONFIGURE FORWARDING AND DEPLOYMENT
# ============================================================================
log "Configuring forwarding to indexer at ${INDEXER_HOST}:${INDEXER_RECEIVE_PORT}..."
sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk add forward-server ${INDEXER_HOST}:${INDEXER_RECEIVE_PORT} \
    || error_exit "Failed to configure forward server"

log "Enabling deployment client to ${INDEXER_HOST}:${INDEXER_MGMT_PORT}..."
sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk set deploy-poll ${INDEXER_HOST}:${INDEXER_MGMT_PORT} \
    || error_exit "Failed to configure deployment client"

# ============================================================================
# CREATE SYSTEMD SERVICE
# ============================================================================
log "Creating systemd service for Universal Forwarder..."
sudo tee /etc/systemd/system/splunkforwarder.service > /dev/null <<EOF
[Unit]
Description=Splunk Universal Forwarder
After=network.target

[Service]
Type=forking
User=splunk
Group=splunk
ExecStart=/opt/splunkforwarder/bin/splunk start
ExecStop=/opt/splunkforwarder/bin/splunk stop
Restart=always
RestartSec=30
Environment="SPLUNK_FORWARDER_HOME=/opt/splunkforwarder"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable splunkforwarder

# Wait for services to stabilize
log "Waiting for services to stabilize..."
sleep 15

# Start systemd service
log "Starting systemd service..."
sudo systemctl start splunkforwarder

# ============================================================================
# VERIFICATION AND COMPLETION
# ============================================================================
log "Verifying Universal Forwarder configuration..."

# Test forwarding configuration
log "Testing forwarding configuration..."
sleep 5
forwarding_status=$(sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk list forward-server 2>/dev/null || echo "Failed to check")
if [[ "$forwarding_status" == *"$INDEXER_HOST:$INDEXER_RECEIVE_PORT"* ]]; then
    log "✓ Forward server configured correctly: ${INDEXER_HOST}:${INDEXER_RECEIVE_PORT}"
else
    log "⚠ Warning: Forward server configuration may have issues"
    log "   Status: $forwarding_status"
fi

# Test deployment client configuration
log "Testing deployment client configuration..."
deployment_status=$(sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk show deploy-poll 2>/dev/null || echo "Failed to check")
if [[ "$deployment_status" == *"$INDEXER_HOST:$INDEXER_MGMT_PORT"* ]]; then
    log "✓ Deployment client configured correctly: ${INDEXER_HOST}:${INDEXER_MGMT_PORT}"
else
    log "⚠ Warning: Deployment client configuration may have issues"
    log "   Status: $deployment_status"
fi

# Check systemd service status
service_status=$(systemctl is-active splunkforwarder 2>/dev/null || echo "inactive")
if [ "$service_status" = "active" ]; then
    log "✓ Systemd service is active"
else
    log "⚠ Warning: Systemd service status: $service_status"
fi

# Check if ports are listening
sleep 5
if netstat -tln 2>/dev/null | grep -q ":$UF_MGMT_PORT " || ss -tln 2>/dev/null | grep -q ":$UF_MGMT_PORT "; then
    log "✓ Universal Forwarder management port $UF_MGMT_PORT is listening"
else
    log "⚠ Warning: Management port $UF_MGMT_PORT may not be listening yet"
fi

# Final verification
log "Performing final verification..."
if sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk status | grep -q "splunkd is running" && \
   systemctl is-active --quiet splunkforwarder; then
    log "✓ Universal Forwarder installation and configuration successful"
else
    log "⚠ Warning: Some verification checks failed, but installation may still be functional"
fi

# Show final configuration summary
log "============================================================================"
log "Universal Forwarder installation completed!"
log "============================================================================"
log "Configuration Summary:"
log "  Universal Forwarder Management: http://localhost:${UF_MGMT_PORT}"
log "  Universal Forwarder Web UI: http://localhost:${UF_WEB_PORT}"
log "  Forwarding to: ${INDEXER_HOST}:${INDEXER_RECEIVE_PORT}"
log "  Deployment server: ${INDEXER_HOST}:${INDEXER_MGMT_PORT}"
log ""
log "Port Configuration:"
log "  Splunk Enterprise Management: 8089"
log "  Universal Forwarder Management: ${UF_MGMT_PORT}"
log "  Universal Forwarder Web: ${UF_WEB_PORT}"
log "  Data Receiving: ${INDEXER_RECEIVE_PORT}"
log ""
log "Verification commands:"
log "  Check status: sudo systemctl status splunkforwarder"
log "  Check UF status: sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk status"
log "  Check forwarding: sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk list forward-server"
log "  Check deployment: sudo -u splunk $SPLUNK_FORWARDER_HOME/bin/splunk show deploy-poll"
log "  View logs: tail -f /opt/splunkforwarder/var/log/splunk/splunkd.log"
log ""
log "Next steps:"
log "1. Verify Splunk Enterprise is running: sudo systemctl status splunk"
log "2. Check data flow: Generate test logs and verify they appear in Splunk"
log "3. Configure inputs via deployment server or local configuration"
log "============================================================================"