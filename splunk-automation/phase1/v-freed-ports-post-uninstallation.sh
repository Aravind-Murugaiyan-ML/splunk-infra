#!/bin/bash

# Splunk Ports and Services Verification Script
# Verifies all Splunk-related ports and services are completely freed up

echo "=== Splunk Ports and Services Verification ==="
echo "Timestamp: $(date)"
echo

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
FREE_PORTS=0
USED_PORTS=0
TOTAL_CHECKS=0

print_result() {
    local status=$1
    local message=$2
    case $status in
        "FREE")
            echo -e "${GREEN}✓ FREE${NC} - $message"
            ((FREE_PORTS++))
            ;;
        "USED")
            echo -e "${RED}✗ USED${NC} - $message"
            ((USED_PORTS++))
            ;;
        "INFO")
            echo -e "${BLUE}ℹ INFO${NC} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠ WARN${NC} - $message"
            ;;
    esac
    ((TOTAL_CHECKS++))
}

# Function to check if a port is in use
check_port() {
    local port=$1
    local description=$2
    local service_hint=$3
    
    # Check with netstat and ss (fallback)
    local is_listening=false
    
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ":$port "; then
            is_listening=true
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tln 2>/dev/null | grep -q ":$port "; then
            is_listening=true
        fi
    fi
    
    if [ "$is_listening" = true ]; then
        # Get process info
        local process_info=""
        if command -v lsof >/dev/null 2>&1; then
            process_info=$(sudo lsof -i :$port 2>/dev/null | grep LISTEN | head -1)
        elif command -v netstat >/dev/null 2>&1; then
            process_info=$(sudo netstat -tlnp 2>/dev/null | grep ":$port " | head -1)
        fi
        
        print_result "USED" "Port $port ($description) - $service_hint"
        if [ -n "$process_info" ]; then
            echo "     Process: $process_info"
        fi
    else
        print_result "FREE" "Port $port ($description)"
    fi
}

# Function to check for Splunk processes
check_processes() {
    echo -e "\n${BLUE}=== Process Check ===${NC}"
    
    # Check for splunk processes
    splunk_processes=$(ps aux | grep -E "(splunk|/opt/splunk)" | grep -v grep | grep -v "$$" || true)
    
    if [ -n "$splunk_processes" ]; then
        print_result "WARN" "Splunk processes still running:"
        echo "$splunk_processes" | while read line; do
            echo "     $line"
        done
    else
        print_result "FREE" "No Splunk processes running"
    fi
    
    # Check specifically for splunkd
    if pgrep -f splunkd >/dev/null 2>&1; then
        splunkd_pids=$(pgrep -f splunkd)
        print_result "WARN" "splunkd processes found: $splunkd_pids"
    else
        print_result "FREE" "No splunkd processes"
    fi
}

# Function to check systemd services
check_services() {
    echo -e "\n${BLUE}=== Service Check ===${NC}"
    
    # List of Splunk-related services to check
    services=("splunk" "splunkforwarder" "Splunkd")
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^$service"; then
            status=$(systemctl is-active "$service" 2>/dev/null || echo "not-found")
            if [ "$status" = "active" ]; then
                print_result "USED" "Service $service is active"
            elif [ "$status" = "inactive" ]; then
                print_result "WARN" "Service $service exists but inactive"
            else
                print_result "FREE" "Service $service not active ($status)"
            fi
        else
            print_result "FREE" "Service $service not found"
        fi
    done
}

# Function to check directories
check_directories() {
    echo -e "\n${BLUE}=== Directory Check ===${NC}"
    
    directories=("/opt/splunk" "/opt/splunkforwarder")
    
    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            print_result "WARN" "Directory $dir still exists (Size: $size)"
        else
            print_result "FREE" "Directory $dir removed"
        fi
    done
}

# Main port checking
echo -e "${BLUE}=== Port Verification ===${NC}"
echo "Checking all Splunk-related ports..."
echo

# Splunk Enterprise ports
echo "Splunk Enterprise Ports:"
echo "------------------------"
check_port "8000" "Splunk Web Interface" "Splunk Enterprise web UI"
check_port "8089" "Splunk Management" "Splunk Enterprise management API"
check_port "9997" "Splunk Receiving" "Splunk Enterprise data receiving"
check_port "8191" "MongoDB/KVStore" "Splunk Enterprise KV Store"

echo
echo "Universal Forwarder Ports:"
echo "-------------------------"
check_port "8188" "UF Management" "Universal Forwarder management"
check_port "8100" "UF Web Interface" "Universal Forwarder web UI"

echo
echo "Custom/Additional Ports:"
echo "-----------------------"
check_port "8989" "Custom Port" "User-specified custom usage"

# Check for any other common Splunk ports
echo
echo "Other Common Splunk Ports:"
echo "-------------------------"
check_port "8065" "Splunk Internal" "Splunk internal communication"
check_port "9887" "Splunk Clustering" "Splunk cluster replication"
check_port "8080" "Alternative Web" "Alternative web interface"

# Additional checks
check_processes
check_services
check_directories

# Network interface check
# Replace lines around 185-195 with:
echo -e "\n${BLUE}=== Network Interface Check ===${NC}"
if command -v netstat >/dev/null 2>&1; then
    splunk_related=$(netstat -tln 2>/dev/null | grep -E ":(8000|8089|8100|8188|8191|8989|9997|8065|9887|8080) " || true)
    if [ -n "$splunk_related" ]; then
        print_result "WARN" "Found ports that might be Splunk-related:"
        echo "$splunk_related" | while read line; do
            echo "     $line"
        done
    else
        print_result "FREE" "No Splunk-related ports detected in netstat"
    fi
fi

# Package check
echo -e "\n${BLUE}=== Package Check ===${NC}"
if command -v dpkg >/dev/null 2>&1; then
    splunk_packages=$(dpkg -l 2>/dev/null | grep splunk || true)
    if [ -n "$splunk_packages" ]; then
        print_result "WARN" "Splunk packages still installed:"
        echo "$splunk_packages" | while read line; do
            echo "     $line"
        done
    else
        print_result "FREE" "No Splunk packages found"
    fi
fi

# Environment variables check
echo -e "\n${BLUE}=== Environment Variables Check ===${NC}"
if env | grep -i splunk >/dev/null 2>&1; then
    splunk_env=$(env | grep -i splunk)
    print_result "WARN" "Splunk environment variables found:"
    echo "$splunk_env" | while read line; do
        echo "     $line"
    done
else
    print_result "FREE" "No Splunk environment variables"
fi

# Check ~/.bashrc for splunk references
if [ -f "$HOME/.bashrc" ]; then
    if grep -i splunk "$HOME/.bashrc" >/dev/null 2>&1; then
        bashrc_refs=$(grep -i splunk "$HOME/.bashrc")
        print_result "WARN" "Splunk references in ~/.bashrc:"
        echo "$bashrc_refs" | while read line; do
            echo "     $line"
        done
    else
        print_result "FREE" "No Splunk references in ~/.bashrc"
    fi
fi

# Detailed port scan for comprehensive check
echo -e "\n${BLUE}=== Comprehensive Port Scan ===${NC}"
echo "Scanning all listening ports for any missed Splunk-related services..."

all_listening_ports=$(netstat -tln 2>/dev/null | grep LISTEN | awk '{print $4}' | cut -d: -f2 | sort -n | uniq || true)
if [ -n "$all_listening_ports" ]; then
    echo "All currently listening ports:"
    echo "$all_listening_ports" | tr '\n' ' '
    echo
    
    # Check if any process names contain 'splunk'
    suspicious_ports=""
    for port in $all_listening_ports; do
        if command -v lsof >/dev/null 2>&1; then
            process_name=$(sudo lsof -i :$port 2>/dev/null | grep LISTEN | awk '{print $1}' | head -1)
            if echo "$process_name" | grep -qi splunk; then
                suspicious_ports="$suspicious_ports $port"
            fi
        fi
    done
    
    if [ -n "$suspicious_ports" ]; then
        print_result "WARN" "Ports with splunk-related processes:$suspicious_ports"
    else
        print_result "FREE" "No ports showing splunk-related processes"
    fi
fi

# Summary
echo
echo "============================================"
echo "           VERIFICATION SUMMARY"
echo "============================================"
echo "Total checks performed: $TOTAL_CHECKS"
echo -e "${GREEN}Ports/Services free: $FREE_PORTS${NC}"
echo -e "${RED}Ports/Services in use: $USED_PORTS${NC}"
echo

if [ $USED_PORTS -eq 0 ]; then
    echo -e "${GREEN}✓ ALL CLEAR: No Splunk-related ports or services detected${NC}"
    echo "System appears to be completely free of Splunk installations."
    exit_code=0
else
    echo -e "${YELLOW}⚠ ATTENTION: $USED_PORTS ports/services still active${NC}"
    echo "Review the items marked as USED or WARN above."
    echo
    echo "If these are intentional (other services using the ports), this is normal."
    echo "If these are leftover Splunk components, consider additional cleanup."
    exit_code=1
fi

echo
echo "Verification completed at: $(date)"
echo
echo "Common port reference:"
echo "• 8000  - Splunk Enterprise Web UI"
echo "• 8089  - Splunk Enterprise Management API"
echo "• 8100  - Universal Forwarder Web UI"
echo "• 8188  - Universal Forwarder Management"
echo "• 8191  - Splunk KV Store (MongoDB)"
echo "• 8989  - Your custom usage"
echo "• 9997  - Splunk Data Receiving"

exit $exit_code