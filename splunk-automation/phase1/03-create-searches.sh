#!/bin/bash

# Create Basic Saved Searches Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/phase1-searches.log"
SPLUNK_HOME=/opt/splunk

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Creating basic saved searches..."

# Create savedsearches.conf
sudo -u splunk tee $SPLUNK_HOME/etc/system/local/savedsearches.conf > /dev/null <<'EOF'
[System Health Hourly]
search = index=main earliest=-1h | stats count by host, sourcetype | sort -count
dispatch.earliest_time = -1h@h
dispatch.latest_time = now

cron_schedule = 0 * * * *
description = Hourly system health check

[Error Summary Daily]
search = index=main (ERROR OR error OR Error OR CRITICAL OR critical) earliest=-24h | stats count by host, source | sort -count
dispatch.earliest_time = -24h@d
dispatch.latest_time = now
enableSched = 1
cron_schedule = 0 9 * * *
description = Daily error summary report

[Data Ingestion Status]
search = index=_internal source=*metrics.log group=per_index_thruput | stats sum(kb) as total_kb by series | sort -total_kb
dispatch.earliest_time = -30m@m
dispatch.latest_time = now
enableSched = 1
cron_schedule = */30 * * * *
description = Data ingestion monitoring

[License Usage Check]
search = index=_internal source=*license_usage.log type=Usage | stats sum(b) as bytes_used by pool | eval gb_used=round(bytes_used/1024/1024/1024,2)
dispatch.earliest_time = -1d@d
dispatch.latest_time = now
enableSched = 1
cron_schedule = 0 8 * * *
description = Daily license usage check
EOF

# Restart Splunk to apply saved searches
log "Restarting Splunk to apply saved searches..."
sudo -u splunk $SPLUNK_HOME/bin/splunk restart

log "Basic saved searches created successfully"