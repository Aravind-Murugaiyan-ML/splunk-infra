# Makefile for managing Splunk service operations
SPLUNK_HOME = /opt/splunk
SPLUNK_USER = splunk
SPLUNK_FORWARDER_HOME = /opt/splunkforwarder

.PHONY: all start-splunk start-service check-status 

# Default target: start Splunk manually, then enable and check systemd service
all: start-splunk start-service check-status

# Start Splunk manually as the splunk user
start-splunk: ## Start Splunk manually as the splunk user
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Starting Splunk manually..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk start || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start Splunk"; exit 1; }

# Start Splunk manually as the splunk user
restart-splunk: ## Start Splunk manually as the splunk user
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Re-starting Splunk manually..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk restart || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start Splunk"; exit 1; }

stop-splunk: ## stop the Splunk systemd service
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Splunk systemd service..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk stop || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Splunk service"; exit 1; }

status-splunk: ## Check the status of the Splunk process
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Checking Splunk status..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk status || true

# Start Splunk's Forwarder manually as the splunk user
start-splunk-forwarder: ## Start Splunk Forwarder manually as the splunk user
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Starting Universal Forwarder..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_FORWARDER_HOME)/bin/splunk start --accept-license --answer-yes --no-prompt \
    || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start Universal Forwarder"; exit 1; }

# Restart Splunk manually as the Splunk's Forwarder user
restart-forwarder: ## Restart Universal Forwarder manually as the splunk user
	@$(call log,Restarting Universal Forwarder...)
	@sudo -u $(SPLUNK_USER) $(SPLUNK_FORWARDER_HOME)/bin/splunk restart || { $(call log,ERROR: Failed to restart Universal Forwarder); exit 1; }
	@$(call log,Sleeping for 30 seconds to allow restart...)
	@sleep 30
	@$(call log,✓ Universal Forwarder restarted)

stop-splunk-forwarder: ## Stop Splunk Forwarder manually as the splunk user
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Universal Forwarder process..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_FORWARDER_HOME)/bin/splunk stop || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Universal Forwarder service"; exit 1; }

status-splunk-forwarder: ## Check the status of the Splunk's Forwarder process
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Checking Universal Forwarder status..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_FORWARDER_HOME)/bin/splunk status || true

# Check the status of the Splunk systemd service
check-splunk-service-status: ## Check the status of the Splunk systemd service
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Checking Splunk service status..."
	@sudo systemctl status splunk || true
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Splunk service status check completed."

# Start the Splunk service 
start-splunk-service: ## Start the Splunk systemd service
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Starting Splunk systemd service..."
	@sudo systemctl start splunk || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start Splunk service"; exit 1; }
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Splunk service started successfully."

# Stop the Splunk service
stop-splunk-service: ## Stop the Splunk systemd service and Splunk process
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Splunk service..."
	@sudo systemctl stop splunk || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Splunk systemd service"; exit 1; }
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Splunk process..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk stop || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Splunk process"; exit 1; }

# Check the status of the Splunk systemd service
check-splunk-forwarder-service-status: ## Check the status of the Splunk systemd service
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Checking Splunk-forwarder service status..."
	@sudo systemctl status splunkforwarder || true
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Splunk-forwarder service status check completed."

# Start the Splunk service 
start-splunk-forwarder-service: ## Start the Splunk systemd service
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Starting Splunk-forwarder systemd service..."
	@sudo systemctl start splunkforwarder || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start Splunk service"; exit 1; }
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Splunk-forwarder service started successfully."

# Stop the Splunk service
stop-splunk-forwarder-service: ## Stop the Splunk systemd service and Splunk process
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Splunk-forwarder service..."
	@sudo systemctl stop splunkforwarder || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Splunk systemd service"; exit 1; }
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Splunk-forwarder process..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_FORWARDER_HOME)/bin/splunk stop || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Splunk process"; exit 1; }

list-active-forwards: ## List active forwarders
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Listing active forwarders..."
	@sudo -u splunk /opt/splunkforwarder/bin/splunk list forward-server

tail-splunkforwarder-splunkd-logs: ## Tail Splunk-forwarder logs
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Tailing Splunk-forwarder logs..."
	@sudo tail -f /opt/splunkforwarder/var/log/splunk/splunkd.log

help: ## Display help information
	@echo "$(GREEN)Splunk Service Management Commands$(NC)"
	@echo "=========================="
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*##.*$$' Makefile | sort | cut -d: -f1 | while read target; do \
		desc=$$(grep "^$$target:.*##" Makefile | sed 's/.*##[[:space:]]*//' ); \
		printf "  $(GREEN)%-25s$(NC) %s\n" "$$target" "$$desc"; \
	done
	@echo ""