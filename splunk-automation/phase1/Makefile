# Makefile for setting up WSL-2 Ubuntu environment for Splunk
SPLUNK_USER = splunk
SPLUNK_HOME = /opt/splunk
SPLUNK_FORWARDER_HOME = /opt/splunkforwarder
SCRIPTS_DIR = /home/splunk/scripts

.PHONY: all update-system install-packages create-user setup-dirs configure-systemd

# Default target: run all setup tasks
all: update-system install-packages create-user setup-dirs configure-systemd

# Update WSL-2 Ubuntu environment
update-system: ## Update and upgrade WSL-2 Ubuntu environment
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Updating and upgrading system..."
	@sudo apt update && sudo apt upgrade -y || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to update and upgrade system"; exit 1; }

# Install required packages
install-packages: ## Install required packages (wget, curl, tar, systemd, net-tools)
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Installing required packages..."
	@sudo apt install -y wget curl tar systemd net-tools || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to install packages"; exit 1; }

# Create splunk user
create-user: ## Create splunk user with bash shell and sudo privileges
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Creating splunk user..."
	@sudo useradd -m -s /bin/bash $(SPLUNK_USER) || true
	@sudo usermod -aG sudo $(SPLUNK_USER) || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to configure splunk user"; exit 1; }

# Set up directory structure
setup-dirs: ## Set up directories for Splunk and scripts
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Setting up directory structure..."
	@sudo mkdir -p $(SPLUNK_HOME) $(SPLUNK_FORWARDER_HOME) $(SCRIPTS_DIR) || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to create directories"; exit 1; }
	@sudo chown -R $(SPLUNK_USER):$(SPLUNK_USER) $(SPLUNK_HOME) $(SPLUNK_FORWARDER_HOME) $(SCRIPTS_DIR) || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to set directory ownership"; exit 1; }

# Configure systemd for WSL-2
configure-systemd: ## Configure systemd for WSL-2 compatibility
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Configuring systemd for WSL-2..."
	@echo 'if [ -z "$$(pgrep systemd)" ]; then sudo /usr/lib/systemd/systemd --system --unit=basic.target & disown; fi' >> ~/.bashrc || { echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to configure systemd in .bashrc"; exit 1; }
	@echo "[$(shell date '+%Y-%m-%d %H:%M:%S')] Systemd configuration completed. Source ~/.bashrc or restart your shell to apply."

help: ## Display help information
	@echo "$(GREEN)WSL-2 Splunk Environment Setup Commands$(NC)"
	@echo "=========================="
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*##.*$$' Makefile | sort | cut -d: -f1 | while read target; do \
		desc=$$(grep "^$$target:.*##" Makefile | sed 's/.*##[[:space:]]*//' ); \
		printf "  $(GREEN)%-25s$(NC) %s\n" "$$target" "$$desc"; \
	done
	@echo ""
	@echo "execution order: update-system->install-packages->create-user->setup-dirs->configure-systemd"
	@echo ""