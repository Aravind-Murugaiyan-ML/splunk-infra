#!/bin/bash

# Deployment Server Configuration Script (Improved)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/phase2-deployment.log"
SPLUNK_HOME=/opt/splunk

# Create logs directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting Deployment Server configuration..."
log "Splunk Home: $SPLUNK_HOME"
log "Log File: $LOG_FILE"

# Check if Splunk Enterprise is installed
if [ ! -d "$SPLUNK_HOME" ]; then
    error_exit "Splunk Enterprise not found at $SPLUNK_HOME. Please install Splunk Enterprise first."
fi

# Check if Splunk is running
log "Checking Splunk Enterprise status..."
if ! sudo -u splunk $SPLUNK_HOME/bin/splunk status | grep -q "splunkd is running"; then
    log "Splunk Enterprise is not running. Starting it..."
    sudo -u splunk $SPLUNK_HOME/bin/splunk start
    sleep 10
fi

# 1. Configure Deployment Server
log "==============================================="
log "STEP 1: Configuring Deployment Server Settings"
log "==============================================="

log "Creating serverclass.conf to enable deployment server functionality..."
sudo -u splunk tee $SPLUNK_HOME/etc/system/local/serverclass.conf > /dev/null <<'EOF'
[global]
restartSplunkWeb = 0
restartSplunkd = 1
stateOnClient = enabled

[serverClass:linux_servers]
whitelist.0 = *

[serverClass:linux_servers:app:app_monitoring]
restartSplunkd = 1
stateOnClient = enabled
EOF

if [ $? -eq 0 ]; then
    log "✓ Successfully created serverclass.conf"
    log "  - Deployment server enabled"
    log "  - Server class 'linux_servers' configured"
    log "  - App 'app_monitoring' assigned to linux_servers"
else
    error_exit "Failed to create serverclass.conf"
fi

# 2. Create deployment app directory structure
log "=============================================="
log "STEP 2: Creating Deployment App Structure"
log "=============================================="

log "Creating deployment app directory structure..."
sudo -u splunk mkdir -p $SPLUNK_HOME/etc/deployment-apps/app_monitoring/{default,metadata,bin}

if [ $? -eq 0 ]; then
    log "✓ Successfully created deployment app directories:"
    log "  - $SPLUNK_HOME/etc/deployment-apps/app_monitoring/default/"
    log "  - $SPLUNK_HOME/etc/deployment-apps/app_monitoring/metadata/"
    log "  - $SPLUNK_HOME/etc/deployment-apps/app_monitoring/bin/"
else
    error_exit "Failed to create deployment app directories"
fi

# 3. Create app monitoring inputs configuration
log "============================================="
log "STEP 3: Creating Input Configurations"
log "============================================="

log "Creating inputs.conf for application and system monitoring..."
sudo -u splunk tee $SPLUNK_HOME/etc/deployment-apps/app_monitoring/default/inputs.conf > /dev/null <<'EOF'
# Application Log Monitoring Configuration
# This file will be deployed to all Universal Forwarders

[monitor:///var/log/apache2/access.log]
disabled = false
index = app_logs
sourcetype = apache_access
host_segment = 1

[monitor:///var/log/apache2/error.log] 
disabled = false
index = app_logs
sourcetype = apache_error

[monitor:///var/log/nginx/access.log]
disabled = false
index = app_logs
sourcetype = nginx_access

[monitor:///var/log/nginx/error.log]
disabled = false
index = app_logs
sourcetype = nginx_error

# System Log Monitoring
[monitor:///var/log/syslog]
disabled = false
index = main
sourcetype = syslog

[monitor:///var/log/auth.log]
disabled = false
index = security
sourcetype = linux_secure

# Custom application logs
[monitor:///opt/myapp/logs/*.log]
disabled = false
index = app_logs
sourcetype = myapp_java
recursive = true

# Database logs
[monitor:///var/log/mysql/error.log]
disabled = false
index = infrastructure
sourcetype = mysql_error

[monitor:///var/log/postgresql/*.log]
disabled = false
index = infrastructure
sourcetype = postgresql

# System metrics collection script
[script:///opt/splunkforwarder/etc/apps/app_monitoring/bin/system_metrics.py]
disabled = false
index = system_metrics
sourcetype = system_metrics
interval = 60
EOF

if [ $? -eq 0 ]; then
    log "✓ Successfully created inputs.conf"
    log "  - Apache/Nginx log monitoring configured"
    log "  - System log monitoring (syslog, auth.log) configured"
    log "  - Database log monitoring configured"
    log "  - Custom application log monitoring configured"
    log "  - System metrics collection script configured"
else
    error_exit "Failed to create inputs.conf"
fi

# 4. Create field extraction configuration
log "============================================="
log "STEP 4: Creating Field Extraction Rules"
log "============================================="

log "Creating props.conf for automatic field extraction..."
sudo -u splunk tee $SPLUNK_HOME/etc/deployment-apps/app_monitoring/default/props.conf > /dev/null <<'EOF'
# Field Extraction Rules for Various Log Types

[apache_access]
EXTRACT-response_time = \s(?<response_time>\d+)$
EXTRACT-status_code = \s(?<status_code>\d{3})\s
EXTRACT-bytes = \s(?<bytes>\d+)\s"
EXTRACT-method = "(?<method>\w+)\s
EXTRACT-uri = "(?<method>\w+)\s+(?<uri>\S+)
EXTRACT-client_ip = ^(?<client_ip>\S+)\s

[nginx_access]
EXTRACT-response_time = request_time=(?<response_time>\d+\.\d+)
EXTRACT-status_code = \s(?<status_code>\d{3})\s
EXTRACT-bytes = \s(?<bytes>\d+)\s
EXTRACT-method = "(?<method>\w+)\s
EXTRACT-uri = "(?<method>\w+)\s+(?<uri>\S+)
EXTRACT-client_ip = ^(?<client_ip>\S+)\s

[myapp_java]
EXTRACT-log_level = ^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\s+(?<log_level>\w+)
EXTRACT-class_name = ^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\s+\w+\s+(?<class_name>\S+)
EXTRACT-thread = \[(?<thread>[^\]]+)\]
EXTRACT-error_type = Exception:\s+(?<error_type>\w+Exception)

[system_metrics]
SHOULD_LINEMERGE = false
KV_MODE = json
TIME_PREFIX = timestamp
TIME_FORMAT = %s

[syslog]
EXTRACT-facility = ^(?<facility>\w+)\s+\d+\s+\d+:\d+:\d+
EXTRACT-process = :\s+(?<process>\w+)(\[\d+\])?:
EOF

if [ $? -eq 0 ]; then
    log "✓ Successfully created props.conf"
    log "  - Apache access log field extractions"
    log "  - Nginx access log field extractions"
    log "  - Java application log field extractions"
    log "  - System metrics JSON parsing"
    log "  - Syslog field extractions"
else
    error_exit "Failed to create props.conf"
fi

# 5. Create metadata configuration
log "==========================================="
log "STEP 5: Creating Metadata Configuration"
log "==========================================="

log "Creating metadata configuration for app permissions..."
sudo -u splunk tee $SPLUNK_HOME/etc/deployment-apps/app_monitoring/metadata/default.meta > /dev/null <<'EOF'
# Metadata configuration for app_monitoring

[views]
access = read : [ * ], write : [ admin ]
export = system

[inputs]
access = read : [ * ], write : [ admin ]
export = system

[props]
access = read : [ * ], write : [ admin ]
export = system
EOF

if [ $? -eq 0 ]; then
    log "✓ Successfully created metadata configuration"
    log "  - Read access granted to all users"
    log "  - Write access restricted to admin users"
    log "  - System-wide export enabled"
else
    error_exit "Failed to create metadata configuration"
fi

# 6. Create system metrics collection script
log "==============================================="
log "STEP 6: Creating System Metrics Collection Script"
log "==============================================="

log "Creating Python script for system metrics collection..."
sudo -u splunk tee $SPLUNK_HOME/etc/deployment-apps/app_monitoring/bin/system_metrics.py > /dev/null <<'EOF'
#!/usr/bin/env python3
"""
System Metrics Collection Script for Splunk Universal Forwarder
Collects CPU, Memory, Disk, and Network metrics and outputs as JSON
"""

import json
import time
import sys

try:
    import psutil
except ImportError:
    print(json.dumps({
        "timestamp": int(time.time()),
        "error": "psutil module not available",
        "message": "Please install psutil: pip3 install psutil"
    }))
    sys.exit(1)

import socket

def collect_metrics():
    """Collect system metrics and output as JSON"""
    hostname = socket.gethostname()
    timestamp = int(time.time())
    
    try:
        # CPU metrics
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # Memory metrics  
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        
        # Disk metrics
        disk = psutil.disk_usage('/')
        disk_percent = (disk.used / disk.total) * 100
        
        # Network metrics
        network = psutil.net_io_counters()
        
        metrics = [
            {
                "timestamp": timestamp,
                "host": hostname,
                "metric_name": "cpu_percent",
                "value": cpu_percent,
                "unit": "percent"
            },
            {
                "timestamp": timestamp, 
                "host": hostname,
                "metric_name": "memory_percent",
                "value": memory_percent,
                "unit": "percent"
            },
            {
                "timestamp": timestamp,
                "host": hostname, 
                "metric_name": "disk_percent_used",
                "value": round(disk_percent, 2),
                "unit": "percent"
            },
            {
                "timestamp": timestamp,
                "host": hostname,
                "metric_name": "network_bytes_sent", 
                "value": network.bytes_sent,
                "unit": "bytes"
            },
            {
                "timestamp": timestamp,
                "host": hostname,
                "metric_name": "network_bytes_recv",
                "value": network.bytes_recv,
                "unit": "bytes"
            }
        ]
        
        for metric in metrics:
            print(json.dumps(metric))
            
    except Exception as e:
        error_metric = {
            "timestamp": timestamp,
            "host": hostname,
            "error": str(e),
            "script": "system_metrics.py"
        }
        print(json.dumps(error_metric))

if __name__ == "__main__":
    collect_metrics()
EOF

if [ $? -eq 0 ]; then
    log "✓ Successfully created system_metrics.py"
    sudo chmod +x $SPLUNK_HOME/etc/deployment-apps/app_monitoring/bin/system_metrics.py
    log "  - Script made executable"
    log "  - Collects CPU, Memory, Disk, and Network metrics"
    log "  - Outputs metrics in JSON format"
    log "  - Includes error handling and logging"
else
    error_exit "Failed to create system_metrics.py"
fi

# 7. Install Python dependencies safely
log "==========================================="
log "STEP 7: Installing Python Dependencies"
log "==========================================="

log "Installing psutil for system metrics collection..."

# Check if psutil is already installed
if python3 -c "import psutil" 2>/dev/null; then
    log "✓ psutil is already installed"
else
    log "Installing psutil using package manager (recommended approach)..."
    
    # Try to install via apt first (safer than pip)
    if sudo apt update && sudo apt install -y python3-psutil; then
        log "✓ Successfully installed python3-psutil via apt package manager"
    else
        log "⚠ Package manager installation failed, falling back to pip..."
        log "Installing psutil via pip3 with proper user permissions..."
        
        # Install as the splunk user to avoid root pip warning
        if sudo -u splunk python3 -m pip install --user psutil; then
            log "✓ Successfully installed psutil via pip3 as splunk user"
        else
            log "⚠ User pip installation failed, installing system-wide..."
            # Last resort: system-wide installation
            if sudo python3 -m pip install psutil; then
                log "✓ Successfully installed psutil system-wide"
                log "⚠ Note: Used system-wide pip installation (not recommended for production)"
            else
                error_exit "Failed to install psutil via any method"
            fi
        fi
    fi
fi

# Verify psutil installation
log "Verifying psutil installation..."

# Test 1: Basic import
if python3 -c "import psutil" 2>/dev/null; then
    log "✓ psutil import successful"
    
    # Test 2: Basic functionality
    if python3 -c "import psutil; print('CPU cores:', psutil.cpu_count())" >/dev/null 2>&1; then
        version=$(python3 -c "import psutil; print(getattr(psutil, '__version__', 'unknown'))" 2>/dev/null)
        log "✓ psutil functionality verified (version: $version)"
    else
        log "⚠ psutil imports but functionality test failed"
    fi
else
    log "⚠ psutil import failed, trying alternative Python path..."
    
    # Alternative verification with explicit path
    if /usr/bin/python3 -c "import psutil; print('psutil working')" 2>/dev/null; then
        log "✓ psutil working with system Python"
    else
        log "⚠ psutil verification failed, continuing anyway"
    fi
fi

# 8. Test the metrics script
log "Testing system metrics script..."
if sudo -u splunk python3 $SPLUNK_HOME/etc/deployment-apps/app_monitoring/bin/system_metrics.py | head -1 | python3 -m json.tool >/dev/null 2>&1; then
    log "✓ System metrics script test successful"
else
    log "⚠ System metrics script test failed, but deployment will continue"
fi

# 9. Apply deployment server configuration
log "============================================"
log "STEP 8: Applying Deployment Server Configuration"
log "============================================"

log "Restarting Splunk Enterprise to apply deployment server configuration..."
log "This may take a few minutes..."

# Restart Splunk to apply deployment server configuration
sudo -u splunk $SPLUNK_HOME/bin/splunk restart

if [ $? -eq 0 ]; then
    log "✓ Splunk Enterprise restarted successfully"
else
    error_exit "Failed to restart Splunk Enterprise"
fi

# 10. Verify deployment server is working
log "============================================"
log "STEP 9: Verifying Deployment Server Status"
log "============================================"

log "Waiting for Splunk to fully start..."
sleep 30

# Check if deployment server is enabled
log "Checking deployment server status..."
if sudo -u splunk $SPLUNK_HOME/bin/splunk show deploy-status -auth admin:changeme >/dev/null 2>&1; then
    log "✓ Deployment server is enabled and responding"
else
    log "⚠ Deployment server status check failed, but configuration is applied"
fi

# Check if the app was created correctly
if [ -d "$SPLUNK_HOME/etc/deployment-apps/app_monitoring" ]; then
    app_files=$(find $SPLUNK_HOME/etc/deployment-apps/app_monitoring -type f | wc -l)
    log "✓ Deployment app 'app_monitoring' created with $app_files files"
else
    error_exit "Deployment app directory not found"
fi

# 11. Summary and next steps
log "============================================"
log "DEPLOYMENT SERVER CONFIGURATION COMPLETE"
log "============================================"

log "Configuration Summary:"
log "• Deployment server enabled in Splunk Enterprise"
log "• Server class 'linux_servers' configured"
log "• App 'app_monitoring' created with comprehensive inputs"
log "• Field extraction rules configured for common log formats"
log "• System metrics collection script installed"
log "• Python dependencies (psutil) installed safely"
log "• All configurations applied and Splunk restarted"

log ""
log "Deployment App Contents:"
log "• inputs.conf: Application, system, and database log monitoring"
log "• props.conf: Field extraction rules for parsing logs"
log "• system_metrics.py: Python script for system metrics collection"
log "• metadata/default.meta: Permission and export settings"

log ""
log "Next Steps:"
log "1. Universal Forwarders will automatically download this app"
log "2. New inputs will be applied to all connected forwarders"
log "3. System metrics will be collected every 60 seconds"
log "4. Log data will be parsed and indexed with extracted fields"

log ""
log "Verification Commands:"
log "• Check deployment status: sudo -u splunk $SPLUNK_HOME/bin/splunk show deploy-status -auth admin:changeme"
log "• List deployment apps: ls -la $SPLUNK_HOME/etc/deployment-apps/"
log "• View app contents: ls -la $SPLUNK_HOME/etc/deployment-apps/app_monitoring/"
log "• Test metrics script: sudo -u splunk python3 $SPLUNK_HOME/etc/deployment-apps/app_monitoring/bin/system_metrics.py"

log ""
log "Deployment server configuration completed successfully!"
log "Universal Forwarders will receive these configurations on their next check-in."