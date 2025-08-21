#!/bin/bash

# Basic Splunk Configuration Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/phase1-config.log"
CONFIG_DIR="$SCRIPT_DIR/../configs"

# Source environment
export SPLUNK_HOME=/opt/splunk
export PATH=$SPLUNK_HOME/bin:$PATH

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting basic Splunk configuration..."

# Wait for Splunk to be ready
log "Waiting for Splunk to be ready..."
for i in {1..60}; do
    if curl -s http://localhost:8000 > /dev/null 2>&1; then
        log "Splunk is ready"
        break
    fi
    sleep 5
    log "Waiting... ($i/60)"
done

# Create indexes
log "Creating custom indexes..."
sudo -u splunk $SPLUNK_HOME/bin/splunk add index app_logs -maxDataSize 10000 -maxHotBuckets 10 \
    || error_exit "Failed to create app_logs index"

sudo -u splunk $SPLUNK_HOME/bin/splunk add index system_metrics -maxDataSize 5000 -maxHotBuckets 5 \
    || error_exit "Failed to create system_metrics index"

sudo -u splunk $SPLUNK_HOME/bin/splunk add index infrastructure -maxDataSize 10000 -maxHotBuckets 10 \
    || error_exit "Failed to create infrastructure index"

sudo -u splunk $SPLUNK_HOME/bin/splunk add index security -maxDataSize 5000 -maxHotBuckets 5 \
    || error_exit "Failed to create security index"

# Configure basic inputs for system logs
log "Configuring system log inputs..."

# Create inputs.conf
sudo -u splunk tee $SPLUNK_HOME/etc/system/local/inputs.conf > /dev/null <<EOF
[monitor:///var/log/syslog]
disabled = false
index = main
sourcetype = syslog

[monitor:///var/log/auth.log]
disabled = false
index = security
sourcetype = linux_secure

[monitor:///var/log/kern.log]
disabled = false
index = main
sourcetype = linux_kernel

[monitor:///var/log/dmesg]
disabled = false
index = main
sourcetype = linux_dmesg

# WSL-2 specific logs
[monitor:///var/log/dpkg.log]
disabled = false
index = main
sourcetype = dpkg_log
EOF

# Restart Splunk to apply configuration
log "Restarting Splunk to apply configuration..."
sudo -u splunk $SPLUNK_HOME/bin/splunk restart

log "Basic configuration completed successfully"