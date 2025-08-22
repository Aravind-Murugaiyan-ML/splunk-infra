# Makefile for configuring and verifying Splunk Universal Forwarder
SPLUNK_HOME = /opt/splunk
SPLUNK_FORWARDER_HOME = /opt/splunkforwarder
SPLUNK_USER = splunk
LOG_FILE = $(shell pwd)/../logs/phase2-forwarder.log

.PHONY: all configure-forwarder restart-forwarder verify-monitor test-message verify-search help

# Default target: Run all configuration and verification steps
all: verify-monitor test-message verify-search

# Logging function
define log
	echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $(LOG_FILE)
endef

# Verify monitor input
verify-monitor: ## Verify monitor input configuration
	@$(call log,Verifying monitor input configuration...)
	@sudo -u $(SPLUNK_USER) $(SPLUNK_FORWARDER_HOME)/bin/splunk list monitor -auth admin:changeme > /tmp/monitor_output.txt 2>&1 || { $(call log,ERROR: Failed to list monitor inputs); cat /tmp/monitor_output.txt; exit 1; }
	@$(call log,✓ Monitor inputs listed successfully)
	@while read -r line; do echo "[$(shell date '+%Y-%m-%d %H:%M:%S')]   Monitor: $$line" | tee -a $(LOG_FILE); done < /tmp/monitor_output.txt

# Generate test message
test-message: ## Generate test message for Splunk
	@$(call log,Generating test message...)
	@logger "FINAL_TEST_$(shell date +%s): This should work now" || { $(call log,ERROR: Failed to generate test message); exit 1; }
	@$(call log,Sleeping for 90 seconds to allow processing...)
	@sleep 90
	@$(call log,✓ Test message generated)

# Search for test message in Splunk Enterprise
verify-search: ## Search for test message in Splunk Enterprise
	@$(call log,Searching for test message in Splunk Enterprise...)
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk search "index=main FINAL_TEST earliest=-5m" -auth admin:changeme > /tmp/search_output.txt 2>&1 || { $(call log,ERROR: Failed to search for test message); cat /tmp/search_output.txt; exit 1; }
	@if grep -q "FINAL_TEST" /tmp/search_output.txt; then \
		$(call log,✓ Test message found in Splunk Enterprise); \
		while read -r line; do echo "[$(shell date '+%Y-%m-%d %H:%M:%S')]   Search Result: $$line" | tee -a $(LOG_FILE); done < /tmp/search_output.txt; \
	else \
		$(call log,⚠ Warning: Test message not found in Splunk Enterprise); \
		while read -r line; do echo "[$(shell date '+%Y-%m-%d %H:%M:%S')]   Search Output: $$line" | tee -a $(LOG_FILE); done < /tmp/search_output.txt; \
		exit 1; \
	fi
# List information about the deployment clients connected to the Splunk Deployment Server
list-deployment-clients: ## List deployment clients connected to the deployment server
	@$(call log,Listing deployment clients connected to the deployment server...)
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk list deploy-clients -auth admin:changeme > /tmp/deploy_clients.txt 2>&1 || { $(call log,ERROR: Failed to list deployment clients); cat /tmp/deploy_clients.txt; exit 1; }
	@$(call log,✓ Deployment clients listed successfully)
	@while read -r line; do echo "[$(shell date '+%Y-%m-%d %H:%M:%S')]   Client: $$line" | tee -a $(LOG_FILE); done < /tmp/deploy_clients.txt

# Display help information
help: ## Display help information
	@echo "\033[32mSplunk Universal Forwarder Configuration and Verification Commands\033[0m"
	@echo "=========================="
	@echo ""
	@echo "\033[33mAvailable targets:\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*##.*$$' $(lastword $(MAKEFILE_LIST)) | sort | cut -d: -f1 | while read target; do \
		desc=$$(grep "^$$target:.*##" $(lastword $(MAKEFILE_LIST)) | sed 's/.*##[[:space:]]*//'); \
		printf "  \033[32m%-25s\033[0m %s\n" "$$target" "$$desc"; \
	done
	@echo ""
