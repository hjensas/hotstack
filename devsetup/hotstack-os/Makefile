.PHONY: help setup build config start stop restart clean status post-setup logs install-client smoke-test smoke-test-cleanup install-deps install uninstall

# Default data directory (can be overridden via environment variable or .env file)
export HOTSTACK_DATA_DIR ?= /var/lib/hotstack-os

# Script directory
SCRIPT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/scripts

# Reusable root privilege check
# Usage: $(call require-root,target-name)
define require-root
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "Error: This command requires root privileges."; \
		echo "Please run: sudo make $(1)"; \
		exit 1; \
	fi
endef

help:
	@echo "HotStack-OS Makefile Commands:"
	@echo ""
	@echo "Dependencies:"
	@echo "  sudo make install-deps        - Install system dependencies (packages and services)"
	@echo "  sudo make install-client      - Install OpenStack client packages on host (optional)"
	@echo ""
	@echo "Podman-Compose Deployment:"
	@echo "  sudo make setup               - Setup host for podman-compose (includes install-deps)"
	@echo "  sudo make build               - Build all container images"
	@echo "  sudo make config              - Prepare runtime configuration files"
	@echo "  sudo make start               - Start all services (includes config)"
	@echo "  sudo make stop                - Stop all services"
	@echo "  sudo make restart             - Restart all services"
	@echo "  sudo make clean               - Complete reset: stop containers, remove all data, NFS, and host setup"
	@echo ""
	@echo "Systemd Deployment:"
	@echo "  sudo make install             - Install HotStack-OS as systemd services (requires: install-deps, build)"
	@echo "  sudo make uninstall           - Remove systemd services and cleanup"
	@echo ""
	@echo "Operations:"
	@echo "  sudo make status              - Check status of all services"
	@echo "  make post-setup               - Create hotstack project/user, resources, and download/upload images (no sudo required)"
	@echo "  sudo make logs                - View logs from all services"
	@echo ""
	@echo "Testing:"
	@echo "  make smoke-test               - Run smoke test with Heat stack validation (no sudo required)"
	@echo "  make smoke-test-cleanup       - Cleanup smoke test resources (no sudo required)"
	@echo ""
	@echo "Note: Most commands require root privileges. Run with sudo or you'll see an error message."

setup: install-deps
	$(call require-root,setup)
	@./scripts/setup-host.sh

build:
	$(call require-root,build)
	@./scripts/build.sh

config:
	$(call require-root,config)
	@./scripts/config.sh

start: config
	$(call require-root,start)
	@./scripts/start.sh
	@echo "Services starting... run 'make status' to check status"

stop:
	$(call require-root,stop)
	@echo "Stopping all services..."
	podman-compose stop
	podman-compose down --remove-orphans

restart:
	$(call require-root,restart)
	@$(MAKE) stop
	@$(MAKE) start

status:
	$(call require-root,status)
	@./scripts/health-check.sh

install-client:
	$(call require-root,install-client)
	@echo "Installing OpenStack client packages on host..."
	@echo ""
	@if [ -f /etc/centos-release ] || grep -q "Red Hat" /etc/redhat-release 2>/dev/null; then \
		if ! rpm -q centos-release-openstack-epoxy >/dev/null 2>&1; then \
			echo "Installing OpenStack Epoxy repository..."; \
			dnf install -y centos-release-openstack-epoxy; \
		else \
			echo "✓ OpenStack Epoxy repository already installed"; \
		fi; \
	else \
		echo "Detected Fedora or other distro (packages available in standard repos)"; \
	fi
	@echo "Installing OpenStack client packages..."
	@dnf install -y python3-openstackclient python3-heatclient
	@echo ""
	@echo "✓ OpenStack client installation complete"
	@echo ""
	@echo "You can now run 'make post-setup' directly from the host"

post-setup:
	@if ! python3 -c "import openstack" 2>/dev/null; then \
		echo "Error: Python OpenStack SDK not found"; \
		echo ""; \
		echo "The post-setup script requires the OpenStack client packages."; \
		echo ""; \
		echo "Please install: sudo make install-client"; \
		echo ""; \
		exit 1; \
	fi
	@echo "Setting up HotStack resources (project, user, quotas, images)..."
	@echo "This will use admin credentials to create shared resources."
	@echo "Images will be downloaded from GitHub releases."
	@echo ""
	./scripts/post-setup.py

logs:
	$(call require-root,logs)
	podman-compose logs -f

clean:
	$(call require-root,clean)
	@echo ""
	@echo -e "\033[0;31mWARNING: Complete system reset\033[0m"
	@echo "This will remove:"
	@echo "  • All containers and volumes"
	@echo "  • All data (databases, images, VMs, logs)"
	@echo -e "  • \033[1;33mAll libvirt VMs matching pattern 'notapet-<uuid>'\033[0m"
	@echo -e "  • \033[1;33mAll network namespaces (netns-*)\033[0m"
	@echo "  • Cinder NFS exports and data"
	@echo "  • Host network infrastructure (OVS bridges, etc.)"
	@echo ""
	@if [ -z "$$HOTSTACK_CLEANUP_CONFIRM" ]; then \
		read -p "Proceed with complete cleanup? [y/N] " -n 1 -r; \
		echo; \
		if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "Cancelled."; \
			exit 1; \
		fi; \
	else \
		echo "Auto-confirmed via HOTSTACK_CLEANUP_CONFIRM"; \
	fi; \
	./scripts/clean.sh

smoke-test:
	@if ! python3 -c "import openstack" 2>/dev/null; then \
		echo "Error: Python OpenStack SDK not found"; \
		echo ""; \
		echo "The smoke test requires the OpenStack client packages."; \
		echo ""; \
		echo "Please install: sudo make install-client"; \
		echo ""; \
		exit 1; \
	fi
	@echo "Running HotStack-OS smoke test..."
	@echo "This will create a Heat stack with test resources."
	@echo ""
	./scripts/smoke-test.py

smoke-test-cleanup:
	@if ! python3 -c "import openstack" 2>/dev/null; then \
		echo "Error: Python OpenStack SDK not found"; \
		echo ""; \
		echo "Please install: sudo make install-client"; \
		echo ""; \
		exit 1; \
	fi
	@echo "Cleaning up smoke test resources..."
	@echo ""
	./scripts/smoke-test.py --cleanup-only

install-deps:
	$(call require-root,install-deps)
	@$(SCRIPT_DIR)/install-deps.sh

install: install-deps config
	$(call require-root,install)
	@$(SCRIPT_DIR)/install-systemd.sh

uninstall:
	$(call require-root,uninstall)
	@$(SCRIPT_DIR)/uninstall-systemd.sh
