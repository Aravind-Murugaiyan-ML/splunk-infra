.PHONY: setup-git setup-ssh setup-config setup-remote test-connection all clean help

# Default target
all: setup-git

# Complete git setup
setup-git: setup-ssh setup-config setup-remote test-connection
	@echo "Git setup completed successfully!"

# Start SSH agent and add key
setup-ssh:
	@echo "Setting up SSH agent and adding key..."
	@eval "$$(ssh-agent -s)" && ssh-add ~/.ssh/id_gitHub_wsl_ubuntu_22_04_aravind_maple_lab
	@echo "SSH key added successfully"

# Configure git user settings (both local and global)
setup-config:
	@echo "Configuring git user settings..."
	@git config user.name "Aravind-Murugaiyan-ML"
	@git config user.email "aravind.murugaiyan@xoriant.com"
	@git config --global user.name "Aravind-Murugaiyan-ML"
	@git config --global user.email "aravind.murugaiyan@xoriant.com"
	@echo "Git configuration updated"

# Set remote URL
setup-remote:
	@echo "Setting remote URL..."
	@git remote set-url origin git@github-Aravind-Murugaiyan-ML:Aravind-Murugaiyan-ML/mak-qc-self-learn.git
	@echo "Remote URL updated"

# Test SSH connection
test-connection:
	@echo "Testing SSH connection..."
	@ssh -T git@github-Aravind-Murugaiyan-ML || true
	@echo "Connection test completed"

# Individual targets for specific operations
ssh-only: setup-ssh

config-only: setup-config

remote-only: setup-remote

test-only: test-connection

# Show current git configuration
show-config:
	@echo "Current Git Configuration:"
	@echo "=========================="
	@echo "Local config:"
	@git config user.name || echo "No local user.name set"
	@git config user.email || echo "No local user.email set"
	@echo ""
	@echo "Global config:"
	@git config --global user.name || echo "No global user.name set"
	@git config --global user.email || echo "No global user.email set"
	@echo ""
	@echo "Remote URL:"
	@git remote -v

# Clean up (reset to default settings)
clean:
	@echo "Resetting git configuration..."
	@git config --unset user.name || true
	@git config --unset user.email || true
	@echo "Local git config cleared"

# Help target
help:
	@echo "Git Setup Makefile"
	@echo "=================="
	@echo
	@echo "Available targets:"
	@echo "  all (default)    - Run complete git setup"
	@echo "  setup-git        - Run complete git setup (same as all)"
	@echo "  setup-ssh        - Setup SSH agent and add key"
	@echo "  setup-config     - Configure git user settings"
	@echo "  setup-remote     - Set remote URL"
	@echo "  test-connection  - Test SSH connection to GitHub"
	@echo
	@echo "Individual targets:"
	@echo "  ssh-only         - Only setup SSH"
	@echo "  config-only      - Only configure git settings"
	@echo "  remote-only      - Only set remote URL"
	@echo "  test-only        - Only test connection"
	@echo
	@echo "Utility targets:"
	@echo "  show-config      - Show current git configuration"
	@echo "  clean            - Reset local git configuration"
	@echo "  help             - Show this help message"
	@echo
	@echo "Usage: make [target]"
	@echo "Example: make setup-git"