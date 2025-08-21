# Makefile for managing Splunk service operations
SPLUNK_HOME = /opt/splunk
SPLUNK_USER = splunk

.PHONY: all start-splunk start-service check-status stop-service

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

# Check the status of the Splunk systemd service
check-status: ## Check the status of the Splunk systemd service
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Checking Splunk service status..."
	@sudo systemctl status splunk || true
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Splunk service status check completed."

# Start the Splunk service 
start-service: ## Start the Splunk systemd service
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Starting Splunk systemd service..."
	@sudo systemctl start splunk || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start Splunk service"; exit 1; }
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Splunk service started successfully."


# Stop the Splunk service
stop-service: ## Stop the Splunk systemd service and Splunk process
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Splunk service..."
	@sudo systemctl stop splunk || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Splunk systemd service"; exit 1; }
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Stopping Splunk process..."
	@sudo -u $(SPLUNK_USER) $(SPLUNK_HOME)/bin/splunk stop || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to stop Splunk process"; exit 1; }

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