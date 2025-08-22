#!/bin/bash

# Application-Specific Searches Creation Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/phase2-app-searches.log"
SPLUNK_HOME=/opt/splunk

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Creating application-specific searches..."

# Add application monitoring searches to savedsearches.conf
sudo -u splunk tee -a $SPLUNK_HOME/etc/system/local/savedsearches.conf > /dev/null <<'EOF'

[App Response Time Monitoring]
search = index=app_logs sourcetype=nginx_access OR sourcetype=apache_access earliest=-15m | stats avg(response_time) as avg_response_time, count as request_count by uri | sort -avg_response_time | head 20
dispatch.earliest_time = -15m
dispatch.latest_time = now
enableSched = 1
cron_schedule = */15 * * * *
description = Monitor application response times

[Error Rate Trending]
search = index=app_logs sourcetype=myapp_java log_level=ERROR earliest=-5m | timechart span=1m count by class_name | fillnull value=0
dispatch.earliest_time = -5m
dispatch.latest_time = now
enableSched = 1
cron_schedule = */5 * * * *
description = Track error rates by application component

[Database Performance Check]
search = index=infrastructure sourcetype=mysql_error OR sourcetype=postgresql earliest=-1h | stats count by host, sourcetype | sort -count
dispatch.earliest_time = -1h
dispatch.latest_time = now
enableSched = 1
cron_schedule = 0 * * * *
description = Monitor database performance and errors

[System Resource Monitoring]
search = index=system_metrics earliest=-10m | stats avg(value) as avg_value, max(value) as max_value by host, metric_name | sort -avg_value
dispatch.earliest_time = -10m
dispatch.latest_time = now
enableSched = 1
cron_schedule = */10 * * * *
description = Monitor system resource utilization

[User Activity Summary]
search = index=app_logs sourcetype=apache_access OR sourcetype=nginx_access earliest=-1d | stats count as requests, dc(client_ip) as unique_visitors by uri | sort -requests | head 50
dispatch.earliest_time = -1d@d
dispatch.latest_time = now
enableSched = 1
cron_schedule = 0 6 * * *
description = Daily user activity analysis
EOF

# Restart Splunk to apply new searches
sudo -u splunk $SPLUNK_HOME/bin/splunk restart

log "Application-specific searches created successfully"
