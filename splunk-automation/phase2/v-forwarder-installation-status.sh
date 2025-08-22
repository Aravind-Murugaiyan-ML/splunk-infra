#!/bin/bash

# Universal Forwarder Installation Verification Script
echo "=== Universal Forwarder Installation Verification ==="
echo "Timestamp: $(date)"
echo

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
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

# 1. Check Universal Forwarder Process
echo "1. Universal Forwarder Process Check:"
echo "------------------------------------"
if sudo -u splunk /opt/splunkforwarder/bin/splunk status | grep -q "splunkd is running"; then
    pid=$(sudo -u splunk /opt/splunkforwarder/bin/splunk status | grep -o 'PID: [0-9]*' | cut -d' ' -f2)
    print_result "PASS" "Universal Forwarder process is running (PID: $pid)"
else
    print_result "FAIL" "Universal Forwarder process is not running"
fi
echo

# 2. Check Systemd Service
echo "2. Systemd Service Check:"
echo "------------------------"
service_status=$(systemctl is-active splunkforwarder 2>/dev/null || echo "inactive")
case $service_status in
    "active")
        print_result "PASS" "Systemd service is active"
        ;;
    "activating")
        print_result "WARN" "Systemd service is still activating"
        ;;
    "inactive"|"failed")
        print_result "FAIL" "Systemd service is $service_status"
        ;;
    *)
        print_result "WARN" "Systemd service status: $service_status"
        ;;
esac

# Check if service is enabled
if systemctl is-enabled --quiet splunkforwarder 2>/dev/null; then
    print_result "PASS" "Systemd service is enabled for boot"
else
    print_result "WARN" "Systemd service not enabled for boot"
fi
echo

# 3. Port Verification
echo "3. Port Verification:"
echo "--------------------"
# Check if UF management port is listening
if netstat -tln 2>/dev/null | grep -q ":8188 " || ss -tln 2>/dev/null | grep -q ":8188 "; then
    print_result "PASS" "Universal Forwarder management port 8188 is listening"
else
    print_result "WARN" "Universal Forwarder management port 8188 not listening"
fi

# Check if UF web port is listening
if netstat -tln 2>/dev/null | grep -q ":8100 " || ss -tln 2>/dev/null | grep -q ":8100 "; then
    print_result "PASS" "Universal Forwarder web port 8100 is listening"
else
    print_result "WARN" "Universal Forwarder web port 8100 not listening"
fi

# Check if Splunk Enterprise receiving port is listening
if netstat -tln 2>/dev/null | grep -q ":9997 " || ss -tln 2>/dev/null | grep -q ":9997 "; then
    print_result "PASS" "Splunk Enterprise receiving port 9997 is listening"
else
    print_result "FAIL" "Splunk Enterprise receiving port 9997 not listening"
fi
echo

# 4. Forward Server Configuration
echo "4. Forward Server Configuration:"
echo "-------------------------------"
forward_status=$(sudo -u splunk /opt/splunkforwarder/bin/splunk list forward-server 2>/dev/null)
if echo "$forward_status" | grep -q "localhost:9997"; then
    if echo "$forward_status" | grep -A 5 "Active forwards:" | grep -q "localhost:9997"; then
        print_result "PASS" "Forward server configured and active: localhost:9997"
    else
        print_result "WARN" "Forward server configured but not active: localhost:9997"
    fi
else
    print_result "FAIL" "Forward server not configured properly"
fi
echo

# 5. Deployment Client Configuration
echo "5. Deployment Client Configuration:"
echo "----------------------------------"
deploy_status=$(sudo -u splunk /opt/splunkforwarder/bin/splunk show deploy-poll 2>/dev/null)
if echo "$deploy_status" | grep -q "localhost:8089"; then
    print_result "PASS" "Deployment client configured: localhost:8089"
else
    print_result "WARN" "Deployment client not configured properly"
fi
echo

# 6. Configuration Files Check
echo "6. Configuration Files Check:"
echo "----------------------------"
config_files=(
    "/opt/splunkforwarder/etc/system/local/server.conf"
    "/opt/splunkforwarder/etc/system/local/web.conf"
    "/opt/splunkforwarder/etc/system/local/inputs.conf"
)

for file in "${config_files[@]}"; do
    if [ -f "$file" ]; then
        print_result "PASS" "Configuration file exists: $(basename $file)"
    else
        print_result "WARN" "Configuration file missing: $(basename $file)"
    fi
done

# Check for configuration errors
config_check=$(sudo -u splunk /opt/splunkforwarder/bin/splunk btool check 2>&1)
if echo "$config_check" | grep -q -i "error"; then
    print_result "WARN" "Configuration validation found issues"
    echo "$config_check" | grep -i "error" | head -3 | sed 's/^/     /'
else
    print_result "PASS" "Configuration validation passed"
fi
echo

# 7. Log File Analysis
echo "7. Log File Analysis:"
echo "--------------------"
if [ -f /opt/splunkforwarder/var/log/splunk/splunkd.log ]; then
    print_result "PASS" "splunkd.log exists"
    
    # Check for recent errors
    recent_errors=$(sudo tail -100 /opt/splunkforwarder/var/log/splunk/splunkd.log | grep -i "error\|fatal" | wc -l)
    if [ "$recent_errors" -eq 0 ]; then
        print_result "PASS" "No recent errors in logs"
    else
        print_result "WARN" "$recent_errors recent errors found in logs"
        echo "   Recent errors:"
        sudo tail -100 /opt/splunkforwarder/var/log/splunk/splunkd.log | grep -i "error\|fatal" | tail -3 | sed 's/^/     /'
    fi
    
    # Check for successful startup messages
    if sudo tail -50 /opt/splunkforwarder/var/log/splunk/splunkd.log | grep -q "Deployment Client initialized"; then
        print_result "PASS" "Deployment client initialized successfully"
    fi
else
    print_result "FAIL" "splunkd.log not found"
fi
echo

# 8. Data Flow Test
echo "8. Data Flow Test:"
echo "-----------------"
echo "Generating test data..."
test_message="UF_TEST_$(date +%s)_$(whoami)"
logger "$test_message"

echo "Waiting 60 seconds for data processing..."
sleep 60

# Check if test data reached Splunk Enterprise
test_result=$(sudo -u splunk /opt/splunk/bin/splunk search "index=main $test_message earliest=-5m" -output csv -maxout 1 -auth admin:changeme 2>/dev/null | wc -l)
if [ "$test_result" -gt 1 ]; then
    print_result "PASS" "Test data successfully forwarded to Splunk Enterprise"
else
    print_result "WARN" "Test data not found in Splunk Enterprise (may need more time)"
fi
echo

# 9. License and Authentication Check
echo "9. License and Authentication:"
echo "-----------------------------"
# Check if admin user exists
auth_check=$(sudo -u splunk /opt/splunkforwarder/bin/splunk list user -auth admin:changeme 2>/dev/null)
if echo "$auth_check" | grep -q "admin"; then
    print_result "PASS" "Admin user authentication working"
else
    print_result "WARN" "Admin user authentication may have issues"
fi

# Check license usage
license_check=$(sudo -u splunk /opt/splunkforwarder/bin/splunk show license -auth admin:changeme 2>/dev/null)
if echo "$license_check" | grep -q -i "license"; then
    print_result "PASS" "License information accessible"
else
    print_result "WARN" "License information not accessible"
fi
echo

# 10. Environment Variables Check
echo "10. Environment Variables:"
echo "-------------------------"
if env | grep -q "SPLUNK_FORWARDER_HOME"; then
    print_result "PASS" "SPLUNK_FORWARDER_HOME environment variable set"
    echo "     SPLUNK_FORWARDER_HOME: $(env | grep SPLUNK_FORWARDER_HOME | cut -d'=' -f2)"
else
    print_result "WARN" "SPLUNK_FORWARDER_HOME environment variable not set"
fi

# Check if original SPLUNK_HOME is preserved
if env | grep "SPLUNK_HOME" | grep -q "/opt/splunk"; then
    print_result "PASS" "Original SPLUNK_HOME preserved for Splunk Enterprise"
else
    print_result "WARN" "SPLUNK_HOME may have been overwritten"
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
        echo -e "${GREEN}✓ Universal Forwarder is fully operational!${NC}"
        echo
        echo "Your Universal Forwarder is:"
        echo "• Running and healthy"
        echo "• Properly configured for forwarding"
        echo "• Successfully sending data to Splunk Enterprise"
        echo "• Ready for production use"
        exit_code=0
    else
        echo -e "${YELLOW}⚠ Universal Forwarder is mostly operational with minor issues${NC}"
        echo
        echo "Consider addressing the warnings above for optimal performance."
        exit_code=1
    fi
else
    echo -e "${RED}✗ Universal Forwarder has critical issues${NC}"
    echo
    echo "Address the failed checks before proceeding."
    exit_code=2
fi

echo
echo "Quick troubleshooting commands:"
echo "• Check UF process: sudo -u splunk /opt/splunkforwarder/bin/splunk status"
echo "• Check systemd: sudo systemctl status splunkforwarder"
echo "• View logs: sudo tail -f /opt/splunkforwarder/var/log/splunk/splunkd.log"
echo "• Test search: sudo -u splunk /opt/splunk/bin/splunk search 'index=main earliest=-1h' -maxout 5 -auth admin:changeme"
echo "• Check forwarding: sudo -u splunk /opt/splunkforwarder/bin/splunk list forward-server -auth admin:changeme"

echo
echo "If systemd service is not active, try:"
echo "• sudo systemctl stop splunkforwarder"
echo "• sudo systemctl start splunkforwarder"
echo "• sudo systemctl status splunkforwarder"

exit $exit_code