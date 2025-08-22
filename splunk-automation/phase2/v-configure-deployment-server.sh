#!/bin/bash

# Deployment Server Configuration Verification Script
echo "=== Deployment Server Configuration Verification ==="
echo "Timestamp: $(date)"
echo

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SPLUNK_HOME=/opt/splunk
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
        "INFO")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
    esac
}

# 1. Check Splunk Enterprise Status
echo "1. Splunk Enterprise Status:"
echo "----------------------------"
if [ ! -d "$SPLUNK_HOME" ]; then
    print_result "FAIL" "Splunk Enterprise not found at $SPLUNK_HOME"
    exit 1
fi

if sudo -u splunk $SPLUNK_HOME/bin/splunk status | grep -q "splunkd is running"; then
    pid=$(sudo -u splunk $SPLUNK_HOME/bin/splunk status | grep -o 'PID: [0-9]*' | cut -d' ' -f2)
    print_result "PASS" "Splunk Enterprise is running (PID: $pid)"
else
    print_result "FAIL" "Splunk Enterprise is not running"
fi

# Check web interface
web_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 2>/dev/null)
case $web_status in
    "200"|"303")
        print_result "PASS" "Web interface accessible (HTTP $web_status)"
        ;;
    "000")
        print_result "FAIL" "Web interface not accessible"
        ;;
    *)
        print_result "WARN" "Web interface returned HTTP $web_status"
        ;;
esac
echo

# 2. Check Deployment Server Configuration
echo "2. Deployment Server Configuration:"
echo "----------------------------------"
if [ -f "$SPLUNK_HOME/etc/system/local/serverclass.conf" ]; then
    print_result "PASS" "serverclass.conf exists"
    
    # Check content
    if grep -q "\[serverClass:linux_servers\]" "$SPLUNK_HOME/etc/system/local/serverclass.conf"; then
        print_result "PASS" "linux_servers server class configured"
    else
        print_result "FAIL" "linux_servers server class not found"
    fi
    
    if grep -q "app:app_monitoring" "$SPLUNK_HOME/etc/system/local/serverclass.conf"; then
        print_result "PASS" "app_monitoring app assignment configured"
    else
        print_result "FAIL" "app_monitoring app assignment not found"
    fi
else
    print_result "FAIL" "serverclass.conf not found"
fi

# Check deployment server status via Splunk
if sudo -u splunk $SPLUNK_HOME/bin/splunk show deploy-status -auth admin:changeme >/dev/null 2>&1; then
    print_result "PASS" "Deployment server is enabled and responding"
    
    # Get deployment clients count
    clients=$(sudo -u splunk $SPLUNK_HOME/bin/splunk show deploy-status -auth admin:changeme 2>/dev/null | grep -c "serverName" || echo "0")
    print_result "INFO" "Connected deployment clients: $clients"
else
    print_result "WARN" "Deployment server status check failed (may need authentication)"
fi
echo

# 3. Check Deployment App Structure
echo "3. Deployment App Structure:"
echo "---------------------------"
app_dir="$SPLUNK_HOME/etc/deployment-apps/app_monitoring"

if [ -d "$app_dir" ]; then
    print_result "PASS" "app_monitoring deployment app directory exists"
    
    # Check subdirectories
    subdirs=("default" "metadata" "bin")
    for subdir in "${subdirs[@]}"; do
        if [ -d "$app_dir/$subdir" ]; then
            print_result "PASS" "$subdir/ directory exists"
        else
            print_result "FAIL" "$subdir/ directory missing"
        fi
    done
else
    print_result "FAIL" "app_monitoring deployment app directory not found"
fi
echo

# 4. Check Configuration Files
echo "4. Configuration Files:"
echo "----------------------"
config_files=(
    "default/inputs.conf:Input configurations"
    "default/props.conf:Field extraction rules"
    "metadata/default.meta:Metadata and permissions"
    "bin/system_metrics.py:System metrics script"
)

for config in "${config_files[@]}"; do
    file_path="${config%%:*}"
    description="${config##*:}"
    full_path="$app_dir/$file_path"
    
    if [ -f "$full_path" ]; then
        size=$(stat -c%s "$full_path")
        print_result "PASS" "$description exists (${size} bytes)"
        
        # Additional checks for specific files
        case "$file_path" in
            "default/inputs.conf")
                monitor_count=$(grep -c "^\[monitor:" "$full_path" 2>/dev/null || echo "0")
                script_count=$(grep -c "^\[script:" "$full_path" 2>/dev/null || echo "0")
                print_result "INFO" "  Monitor inputs: $monitor_count, Script inputs: $script_count"
                ;;
            "default/props.conf")
                sourcetype_count=$(grep -c "^\[" "$full_path" 2>/dev/null || echo "0")
                extract_count=$(grep -c "^EXTRACT-" "$full_path" 2>/dev/null || echo "0")
                print_result "INFO" "  Sourcetypes: $sourcetype_count, Extractions: $extract_count"
                ;;
            "bin/system_metrics.py")
                if [ -x "$full_path" ]; then
                    print_result "PASS" "  Script is executable"
                else
                    print_result "WARN" "  Script is not executable"
                fi
                ;;
        esac
    else
        print_result "FAIL" "$description missing"
    fi
done
echo

# 5. Check Python Dependencies
echo "5. Python Dependencies:"
echo "----------------------"
# Test psutil import
if python3 -c "import psutil" 2>/dev/null; then
    version=$(python3 -c "import psutil; print(getattr(psutil, '__version__', 'unknown'))" 2>/dev/null)
    print_result "PASS" "psutil is importable (version: $version)"
    
    # Test functionality
    if python3 -c "import psutil; psutil.cpu_percent(); psutil.virtual_memory()" >/dev/null 2>&1; then
        print_result "PASS" "psutil functionality verified"
    else
        print_result "WARN" "psutil import works but functionality test failed"
    fi
else
    print_result "FAIL" "psutil not importable"
fi

# Test system metrics script
if [ -f "$app_dir/bin/system_metrics.py" ]; then
    if sudo -u splunk python3 "$app_dir/bin/system_metrics.py" | head -1 | python3 -m json.tool >/dev/null 2>&1; then
        print_result "PASS" "System metrics script produces valid JSON"
    else
        print_result "WARN" "System metrics script test failed"
        
        # Show error
        echo "     Error output:"
        sudo -u splunk python3 "$app_dir/bin/system_metrics.py" 2>&1 | head -3 | sed 's/^/       /'
    fi
fi
echo

# 6. Check Index Configuration
echo "6. Index Configuration:"
echo "----------------------"
required_indexes=("main" "app_logs" "system_metrics" "infrastructure" "security")

for index in "${required_indexes[@]}"; do
    if sudo -u splunk $SPLUNK_HOME/bin/splunk list index "$index" >/dev/null 2>&1; then
        # Get index stats
        size=$(sudo -u splunk $SPLUNK_HOME/bin/splunk search "|rest /services/data/indexes | search title=\"$index\" | table currentDBSizeMB" -output csv -auth admin:changeme 2>/dev/null | tail -1)
        events=$(sudo -u splunk $SPLUNK_HOME/bin/splunk search "|rest /services/data/indexes | search title=\"$index\" | table totalEventCount" -output csv -auth admin:changeme 2>/dev/null | tail -1)
        
        if [ -n "$size" ] && [ -n "$events" ]; then
            print_result "PASS" "Index '$index' exists (${size}MB, ${events} events)"
        else
            print_result "PASS" "Index '$index' exists"
        fi
    else
        print_result "FAIL" "Index '$index' not found"
    fi
done
echo

# 7. Check Deployment App Deployment Status
echo "7. Deployment Status:"
echo "--------------------"
# Check if any forwarders are connected
if sudo -u splunk $SPLUNK_HOME/bin/splunk list deploy-clients -auth admin:changeme >/dev/null 2>&1; then
    client_count=$(sudo -u splunk $SPLUNK_HOME/bin/splunk list deploy-clients -auth admin:changeme 2>/dev/null | grep -c "serverName" || echo "0")
    
    if [ "$client_count" -gt 0 ]; then
        print_result "PASS" "$client_count deployment clients connected"
        
        # Show client details
        print_result "INFO" "Connected clients:"
        sudo -u splunk $SPLUNK_HOME/bin/splunk list deploy-clients -auth admin:changeme 2>/dev/null | grep "serverName" | head -5 | sed 's/^/       /'
    else
        print_result "INFO" "No deployment clients currently connected"
    fi
else
    print_result "WARN" "Cannot check deployment client status"
fi

# Check app deployment status
if [ -d "$app_dir" ]; then
    app_checksum=$(find "$app_dir" -type f -exec md5sum {} \; | md5sum | cut -d' ' -f1)
    print_result "INFO" "App checksum: ${app_checksum:0:8}... (for tracking deployments)"
fi
echo

# 8. Test Configuration Syntax
echo "8. Configuration Syntax Check:"
echo "------------------------------"
# Check overall configuration
config_check=$(sudo -u splunk $SPLUNK_HOME/bin/splunk btool check 2>&1)
if echo "$config_check" | grep -q -i "error"; then
    print_result "WARN" "Configuration has syntax errors"
    echo "$config_check" | grep -i "error" | head -3 | sed 's/^/       /'
else
    print_result "PASS" "Configuration syntax is valid"
fi

# Check deployment-specific configurations
if sudo -u splunk $SPLUNK_HOME/bin/splunk btool serverclass list --debug >/dev/null 2>&1; then
    print_result "PASS" "Deployment server configuration is valid"
else
    print_result "WARN" "Deployment server configuration has issues"
fi
echo

# 9. Network Connectivity Check
echo "9. Network Connectivity:"
echo "-----------------------"
# Check ports
splunk_ports=("8000:Web Interface" "8089:Management" "8191:KV Store")

for port_info in "${splunk_ports[@]}"; do
    port="${port_info%%:*}"
    description="${port_info##*:}"
    
    if netstat -tln 2>/dev/null | grep -q ":$port " || ss -tln 2>/dev/null | grep -q ":$port "; then
        print_result "PASS" "$description port $port is listening"
    else
        print_result "FAIL" "$description port $port not listening"
    fi
done
echo

# 10. Log Analysis
echo "10. Recent Log Analysis:"
echo "-----------------------"
if sudo [ -f "$SPLUNK_HOME/var/log/splunk/splunkd.log" ]; then
    print_result "PASS" "splunkd.log exists"
    
    # Check for recent errors
    recent_errors=$(sudo tail -100 "$SPLUNK_HOME/var/log/splunk/splunkd.log" | grep -i "error\|fatal" | wc -l)
    if [ "$recent_errors" -eq 0 ]; then
        print_result "PASS" "No recent errors in splunkd.log"
    else
        print_result "WARN" "$recent_errors recent errors found"
        echo "     Recent errors:"
        sudo tail -100 "$SPLUNK_HOME/var/log/splunk/splunkd.log" | grep -i "error\|fatal" | tail -3 | sed 's/^/       /'
    fi
    
    # Check for deployment server messages
    deploy_msgs=$(sudo tail -100 "$SPLUNK_HOME/var/log/splunk/splunkd.log" | grep -i "deployment\|serverclass" | wc -l)
    if [ "$deploy_msgs" -gt 0 ]; then
        print_result "PASS" "Deployment server activity detected in logs"
    else
        print_result "INFO" "No recent deployment server activity in logs"
    fi
else
    print_result "FAIL" "splunkd.log not found"
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
        echo -e "${GREEN}✓ Deployment server configuration is fully operational!${NC}"
        echo
        echo "Your deployment server is ready to:"
        echo "• Deploy configurations to Universal Forwarders"
        echo "• Manage input configurations centrally"
        echo "• Collect system metrics from connected clients"
        echo "• Apply field extraction rules automatically"
        exit_code=0
    else
        echo -e "${YELLOW}⚠ Deployment server is mostly operational with minor issues${NC}"
        echo
        echo "Consider addressing the warnings above for optimal performance."
        exit_code=1
    fi
else
    echo -e "${RED}✗ Deployment server has critical issues${NC}"
    echo
    echo "Address the failed checks before deploying to production."
    exit_code=2
fi

echo
echo "Deployment App Location: $app_dir"
echo "Configuration Files:"
echo "• serverclass.conf: $SPLUNK_HOME/etc/system/local/serverclass.conf"
echo "• App inputs: $app_dir/default/inputs.conf"
echo "• Field extractions: $app_dir/default/props.conf"
echo "• System metrics: $app_dir/bin/system_metrics.py"

echo
echo "Management Commands:"
echo "• Check deployment status: sudo -u splunk $SPLUNK_HOME/bin/splunk show deploy-status -auth admin:changeme"
echo "• List deployment clients: sudo -u splunk $SPLUNK_HOME/bin/splunk list deploy-clients -auth admin:changeme"
echo "• Reload deployment server: sudo -u splunk $SPLUNK_HOME/bin/splunk reload deploy-server -auth admin:changeme"

exit $exit_code