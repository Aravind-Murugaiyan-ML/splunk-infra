#!/bin/bash
# File: verify-phase1-complete.sh
# Comprehensive verification for Phase 1 (basic config + saved searches)

echo "=== Comprehensive Phase 1 Verification ==="
echo "Checking: Basic Configuration + Saved Searches"
echo "================================================"
echo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Success/failure counters
PASS=0
FAIL=0
WARN=0

print_result() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}✓${NC} $message"
            ((PASS++))
            ;;
        "FAIL")
            echo -e "${RED}✗${NC} $message"
            ((FAIL++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠${NC} $message"
            ((WARN++))
            ;;
    esac
}

# Determine correct log directory (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

# If script is in a subdirectory (like phase directories), go up one level
if [[ "$SCRIPT_DIR" == */phase* ]]; then
    LOG_DIR="$SCRIPT_DIR/../logs"
fi

echo "Log directory: $LOG_DIR"
echo

# 1. Check script execution logs
echo "1. Script Execution Logs:"
echo "------------------------"

# Check basic config log
CONFIG_LOG="$LOG_DIR/phase1-config.log"
if [ -f "$CONFIG_LOG" ]; then
    print_result "PASS" "Basic config log file exists ($CONFIG_LOG)"
    if grep -q "Basic configuration completed successfully" "$CONFIG_LOG"; then
        print_result "PASS" "Basic configuration completed successfully"
    else
        print_result "FAIL" "Basic configuration may have failed"
        echo "   Last error lines:"
        grep "ERROR" "$CONFIG_LOG" | tail -3 | sed 's/^/     /'
    fi
else
    print_result "FAIL" "Basic config log file missing ($CONFIG_LOG)"
    # Try to find log files elsewhere
    echo "   Searching for log files..."
    find . -name "phase1-config.log" 2>/dev/null | head -3 | sed 's/^/     Found: /'
fi

# Check saved searches log
SEARCHES_LOG="$LOG_DIR/phase1-searches.log"
if [ -f "$SEARCHES_LOG" ]; then
    print_result "PASS" "Saved searches log file exists ($SEARCHES_LOG)"
    if grep -q "Basic saved searches created successfully" "$SEARCHES_LOG"; then
        print_result "PASS" "Saved searches creation completed successfully"
    else
        print_result "FAIL" "Saved searches creation may have failed"
        echo "   Last error lines:"
        grep "ERROR" "$SEARCHES_LOG" | tail -3 | sed 's/^/     /'
    fi
else
    print_result "FAIL" "Saved searches log file missing ($SEARCHES_LOG)"
    # Try to find log files elsewhere
    echo "   Searching for log files..."
    find . -name "phase1-searches.log" 2>/dev/null | head -3 | sed 's/^/     Found: /'
fi
echo

# 2. Check Splunk service
echo "2. Splunk Service Status:"
echo "------------------------"
if systemctl is-active --quiet splunk 2>/dev/null; then
    print_result "PASS" "Splunk service is running"
    
    # Check service details
    uptime=$(systemctl show splunk --property=ActiveEnterTimestamp --value)
    echo "   Service uptime: $uptime"
    
    # Check if service is enabled
    if systemctl is-enabled --quiet splunk 2>/dev/null; then
        print_result "PASS" "Splunk service is enabled for boot"
    else
        print_result "WARN" "Splunk service not enabled for boot"
    fi
else
    print_result "FAIL" "Splunk service is not running"
    echo "   Service status:"
    systemctl status splunk --no-pager -l | head -10 | sed 's/^/     /'
fi
echo

# 3. Check web interface
echo "3. Web Interface Accessibility:"
echo "------------------------------"
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 2>/dev/null)
if [ "$response" = "200" ] || [ "$response" = "303" ]; then
    print_result "PASS" "Splunk web interface is accessible (HTTP $response)"
    if [ "$response" = "303" ]; then
        echo "     HTTP 303 = Normal redirect to login page"
    fi
elif [ "$response" = "000" ]; then
    print_result "FAIL" "Cannot connect to Splunk web interface"
else
    print_result "WARN" "Splunk web interface returned HTTP $response (unexpected)"
fi

# Check response time
response_time=$(curl -s -w "%{time_total}\n" -o /dev/null http://localhost:8000 2>/dev/null)
if [ -n "$response_time" ]; then
    echo "   Response time: ${response_time}s"
fi
echo

# 4. Check index creation
echo "4. Index Creation:"
echo "-----------------"
expected_indexes=(main app_logs system_metrics infrastructure security)
for index in "${expected_indexes[@]}"; do
    if sudo -u splunk /opt/splunk/bin/splunk list index "$index" >/dev/null 2>&1; then
        print_result "PASS" "Index '$index' exists"
        
        # Get index details
        size=$(sudo -u splunk /opt/splunk/bin/splunk search "|rest /services/data/indexes | search title=\"$index\" | table currentDBSizeMB" -output csv 2>/dev/null | tail -1)
        events=$(sudo -u splunk /opt/splunk/bin/splunk search "|rest /services/data/indexes | search title=\"$index\" | table totalEventCount" -output csv 2>/dev/null | tail -1)
        if [ -n "$size" ] && [ -n "$events" ]; then
            echo "     Size: ${size}MB, Events: $events"
        fi
    else
        print_result "FAIL" "Index '$index' missing"
    fi
done
echo

# 5. Check inputs configuration
echo "5. Inputs Configuration:"
echo "-----------------------"
if [ -f /opt/splunk/etc/system/local/inputs.conf ]; then
    print_result "PASS" "inputs.conf file exists"
    
    # Count monitor inputs
    monitor_count=$(grep -c "^\[monitor:" /opt/splunk/etc/system/local/inputs.conf 2>/dev/null || echo "0")
    print_result "PASS" "$monitor_count monitor inputs configured"
    
    # Check specific inputs
    expected_inputs=("/var/log/syslog" "/var/log/auth.log" "/var/log/kern.log" "/var/log/dmesg" "/var/log/dpkg.log")
    for input in "${expected_inputs[@]}"; do
        if grep -q "monitor://$input" /opt/splunk/etc/system/local/inputs.conf; then
            print_result "PASS" "Monitor input for $input configured"
        else
            print_result "WARN" "Monitor input for $input not found"
        fi
    done
    
    # Check if inputs are active
    active_inputs=$(sudo -u splunk /opt/splunk/bin/splunk list monitor 2>/dev/null | wc -l)
    echo "   Active monitor inputs: $active_inputs"
else
    print_result "FAIL" "inputs.conf file missing"
fi
echo

# 6. Check saved searches configuration
echo "6. Saved Searches Configuration:"
echo "-------------------------------"
if [ -f /opt/splunk/etc/system/local/savedsearches.conf ]; then
    print_result "PASS" "savedsearches.conf file exists"
    
    # Check for expected saved searches
    expected_searches=("System Health Hourly" "Error Summary Daily" "Data Ingestion Status" "License Usage Check")
    for search in "${expected_searches[@]}"; do
        if grep -q "^\[$search\]" /opt/splunk/etc/system/local/savedsearches.conf; then
            print_result "PASS" "Saved search '$search' configured"
            
            # Check if it's scheduled
            if grep -A 10 "^\[$search\]" /opt/splunk/etc/system/local/savedsearches.conf | grep -q "enableSched = 1"; then
                echo "     ✓ Scheduled"
                # Get cron schedule
                cron=$(grep -A 10 "^\[$search\]" /opt/splunk/etc/system/local/savedsearches.conf | grep "cron_schedule" | cut -d'=' -f2 | xargs)
                if [ -n "$cron" ]; then
                    echo "     Schedule: $cron"
                fi
            else
                print_result "WARN" "Search '$search' is not scheduled"
            fi
        else
            print_result "FAIL" "Saved search '$search' not found"
        fi
    done
    
    # Count total saved searches
    total_searches=$(grep -c "^\[.*\]" /opt/splunk/etc/system/local/savedsearches.conf 2>/dev/null || echo "0")
    echo "   Total saved searches: $total_searches"
else
    print_result "FAIL" "savedsearches.conf file missing"
fi
echo

# 7. Check saved searches via Splunk API
echo "7. Saved Searches via Splunk API:"
echo "---------------------------------"
if command -v curl >/dev/null 2>&1; then
    # Check if saved searches are accessible via API
    api_response=$(curl -k -u admin:changeme -s "https://localhost:8089/services/saved/searches" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$api_response" ]; then
        print_result "PASS" "Saved searches API accessible"
        
        # Count searches from API
        search_count=$(echo "$api_response" | grep -o "<title>" | wc -l)
        echo "   API reports $search_count saved searches"
        
        # Check specific searches via API
        for search in "${expected_searches[@]}"; do
            if echo "$api_response" | grep -q "$search"; then
                print_result "PASS" "API confirms '$search' exists"
            else
                print_result "WARN" "API doesn't show '$search'"
            fi
        done
    else
        print_result "WARN" "Cannot access saved searches API (may need authentication setup)"
    fi
else
    print_result "WARN" "curl not available for API testing"
fi
echo

# 8. Check data ingestion
echo "8. Data Ingestion (Recent Activity):"
echo "------------------------------------"
for index in main security; do
    # Try to get recent event count
    count=$(sudo -u splunk /opt/splunk/bin/splunk search "index=$index earliest=-1h" -output csv 2>/dev/null | wc -l 2>/dev/null || echo "1")
    count=$((count - 1)) # Subtract header line
    
    if [ "$count" -gt 0 ]; then
        print_result "PASS" "Index '$index' has $count events in last hour"
        
        # Get latest event timestamp
        latest=$(sudo -u splunk /opt/splunk/bin/splunk search "index=$index latest=1" -output csv 2>/dev/null | tail -1 | cut -d',' -f1 2>/dev/null || echo "N/A")
        if [ "$latest" != "N/A" ] && [ "$latest" != "_time" ]; then
            echo "     Latest event: $latest"
        fi
    else
        print_result "WARN" "Index '$index' has no recent data (may be normal for new installation)"
    fi
done
echo

# 9. Test saved search execution
echo "9. Saved Search Execution Test:"
echo "------------------------------"
# Test one of the saved searches
test_search="System Health Hourly"
echo "Testing execution of '$test_search'..."

# Run the search manually
search_result=$(sudo -u splunk /opt/splunk/bin/splunk search "index=main earliest=-1h | stats count by host, sourcetype | sort -count" -maxout 5 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$search_result" ]; then
    print_result "PASS" "Test search executed successfully"
    echo "   Sample results:"
    echo "$search_result" | head -5 | sed 's/^/     /'
else
    print_result "WARN" "Test search execution failed or returned no results"
fi
echo

# 10. Check file permissions
echo "10. File Permissions Check:"
echo "--------------------------"
# Check ownership of key files
files_to_check=(
    "/opt/splunk/etc/system/local/inputs.conf"
    "/opt/splunk/etc/system/local/savedsearches.conf"
    "/opt/splunk/var/log/splunk"
)

for file in "${files_to_check[@]}"; do
    if [ -e "$file" ]; then
        owner=$(stat -c '%U:%G' "$file" 2>/dev/null)
        if [ "$owner" = "splunk:splunk" ]; then
            print_result "PASS" "$file owned by splunk:splunk"
        else
            print_result "WARN" "$file owned by $owner (expected splunk:splunk)"
        fi
    else
        print_result "WARN" "$file does not exist"
    fi
done
echo

# 11. Check disk space and performance
echo "11. System Resources:"
echo "--------------------"
# Check disk space
disk_usage=$(df /opt/splunk | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$disk_usage" -lt 80 ]; then
    print_result "PASS" "Disk usage: ${disk_usage}% (healthy)"
elif [ "$disk_usage" -lt 90 ]; then
    print_result "WARN" "Disk usage: ${disk_usage}% (monitor closely)"
else
    print_result "FAIL" "Disk usage: ${disk_usage}% (critical)"
fi

# Check memory usage
if command -v free >/dev/null 2>&1; then
    mem_usage=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')
    print_result "PASS" "Memory usage: ${mem_usage}%"
fi

# Check load average
if [ -f /proc/loadavg ]; then
    load_avg=$(cat /proc/loadavg | cut -d' ' -f1)
    print_result "PASS" "Load average: $load_avg"
fi
echo

# Summary
echo "============================================"
echo "           VERIFICATION SUMMARY"
echo "============================================"
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "${RED}Failed:${NC} $FAIL"
echo

if [ $FAIL -eq 0 ]; then
    if [ $WARN -eq 0 ]; then
        echo -e "${GREEN}🎉 All checks passed! Phase 1 is fully operational.${NC}"
        exit_code=0
    else
        echo -e "${YELLOW}✓ Phase 1 is operational with some warnings to review.${NC}"
        exit_code=1
    fi
else
    echo -e "${RED}❌ Phase 1 has issues that need to be addressed.${NC}"
    exit_code=2
fi

echo
echo "Next Steps:"
if [ $FAIL -eq 0 ]; then
    echo "• Phase 1 verification complete"
    echo "• Ready to proceed to Phase 2 (Application Integration)"
    echo "• Access Splunk Web: http://localhost:8000 (admin/changeme)"
else
    echo "• Review failed checks above"
    echo "• Check log files in $LOG_DIR/"
    echo "• Re-run failed scripts if necessary"
fi

echo
echo "Detailed logs available at:"
echo "• Basic config: $CONFIG_LOG"
echo "• Saved searches: $SEARCHES_LOG"

exit $exit_code