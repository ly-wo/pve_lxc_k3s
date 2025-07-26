# PVE LXC K3s Template Generator Makefile

# Variables
TEMPLATE_NAME := alpine-k3s
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_DIR := build
DIST_DIR := dist
CONFIG_DIR := config
SCRIPTS_DIR := scripts
TESTS_DIR := tests

# Default target
.PHONY: all
all: build

# Help target
.PHONY: help
help:
	@echo "PVE LXC K3s Template Generator"
	@echo ""
	@echo "Available targets:"
	@echo "  build          - Build the LXC template"
	@echo "  test           - Run all tests"
	@echo "  test-unit      - Run unit tests"
	@echo "  test-integration - Run integration tests"
	@echo "  test-system    - Run system tests"
	@echo "  test-system-mock - Run system tests in mock mode"
	@echo "  deploy-single  - Deploy single-node cluster"
	@echo "  deploy-multi   - Deploy multi-node cluster"
	@echo "  deploy-cleanup - Clean up deployments"
	@echo "  deploy-status  - Check deployment status"
	@echo "  benchmark      - Run performance benchmarks"
	@echo "  benchmark-startup - Run startup time benchmarks"
	@echo "  benchmark-api  - Run API response time benchmarks"
	@echo "  clean          - Clean build artifacts"
	@echo "  lint           - Run code linting"
	@echo "  package        - Package the template for distribution"
	@echo "  package-info   - Show package information"
	@echo "  package-verify - Verify existing package"
	@echo "  validate       - Validate template package"
	@echo "  validate-quick - Quick template validation"
	@echo "  install-deps   - Install build dependencies"
	@echo "  setup-dev      - Setup development environment"
	@echo "  help           - Show this help message"

# Build targets
.PHONY: build
build: clean setup-build
	@echo "Building LXC template..."
	@mkdir -p $(BUILD_DIR)
	@$(SCRIPTS_DIR)/build-template.sh

.PHONY: setup-build
setup-build:
	@echo "Setting up build environment..."
	@mkdir -p $(BUILD_DIR) $(DIST_DIR)

# Test targets
.PHONY: test
test: test-unit test-integration test-system

.PHONY: test-unit
test-unit:
	@echo "Running unit tests..."
	@if [ -f $(TESTS_DIR)/run-unit-tests.sh ]; then \
		$(TESTS_DIR)/run-unit-tests.sh; \
	else \
		echo "Unit tests not yet implemented"; \
	fi

.PHONY: test-integration
test-integration:
	@echo "Running integration tests..."
	@if [ -f $(TESTS_DIR)/run-integration-tests.sh ]; then \
		$(TESTS_DIR)/run-integration-tests.sh; \
	else \
		echo "Integration tests not yet implemented"; \
	fi

.PHONY: test-system
test-system:
	@echo "Running system tests..."
	@if [ -f $(TESTS_DIR)/run-system-tests.sh ]; then \
		$(TESTS_DIR)/run-system-tests.sh; \
	else \
		echo "System tests not yet implemented"; \
	fi

.PHONY: test-system-mock
test-system-mock:
	@echo "Running system tests in mock mode..."
	@if [ -f $(TESTS_DIR)/run-system-tests.sh ]; then \
		$(TESTS_DIR)/run-system-tests.sh --mock; \
	else \
		echo "System tests not yet implemented"; \
	fi

# Validation targets
.PHONY: validate
validate: package
	@echo "Validating template package..."
	@$(SCRIPTS_DIR)/template-validator.sh validate

.PHONY: validate-quick
validate-quick: package
	@echo "Running quick template validation..."
	@$(SCRIPTS_DIR)/template-validator.sh quick

.PHONY: validate-package-only
validate-package-only:
	@echo "Validating package integrity only..."
	@$(SCRIPTS_DIR)/template-validator.sh package-only

.PHONY: validate-performance
validate-performance: package
	@echo "Running performance validation..."
	@$(SCRIPTS_DIR)/template-validator.sh performance

# Linting
.PHONY: lint
lint:
	@echo "Running shellcheck on scripts..."
	@find $(SCRIPTS_DIR) -name "*.sh" -exec shellcheck {} \; || echo "shellcheck not installed"

# Package targets
.PHONY: package
package: build
	@echo "Packaging template..."
	@mkdir -p output
	@$(SCRIPTS_DIR)/packager.sh package

.PHONY: package-info
package-info:
	@echo "Showing package information..."
	@$(SCRIPTS_DIR)/packager.sh info

.PHONY: package-verify
package-verify:
	@echo "Verifying package..."
	@$(SCRIPTS_DIR)/packager.sh verify

.PHONY: package-clean
package-clean:
	@echo "Cleaning package output..."
	@$(SCRIPTS_DIR)/packager.sh clean

# Deployment targets
.PHONY: deploy-single
deploy-single: package
	@echo "Deploying single-node cluster..."
	@$(SCRIPTS_DIR)/pve-deployment-automation.sh single-node output/*.tar.gz

.PHONY: deploy-multi
deploy-multi: package
	@echo "Deploying multi-node cluster..."
	@$(SCRIPTS_DIR)/pve-deployment-automation.sh multi-node output/*.tar.gz

.PHONY: deploy-cleanup
deploy-cleanup:
	@echo "Cleaning up deployments..."
	@$(SCRIPTS_DIR)/pve-deployment-automation.sh cleanup

.PHONY: deploy-status
deploy-status:
	@echo "Checking deployment status..."
	@$(SCRIPTS_DIR)/pve-deployment-automation.sh status

# Performance testing
.PHONY: benchmark
benchmark: test-system
	@echo "Running performance benchmarks..."
	@echo "Performance benchmarks completed as part of system tests"

.PHONY: benchmark-startup
benchmark-startup:
	@echo "Running startup time benchmarks..."
	@$(TESTS_DIR)/run-system-tests.sh --mock | grep -E "(startup|启动)"

.PHONY: benchmark-api
benchmark-api:
	@echo "Running API response time benchmarks..."
	@$(TESTS_DIR)/run-system-tests.sh --mock | grep -E "(API|api)"

# Development setup
.PHONY: install-deps
install-deps:
	@echo "Installing build dependencies..."
	@command -v shellcheck >/dev/null 2>&1 || echo "Consider installing shellcheck for linting"
	@command -v bats >/dev/null 2>&1 || echo "Consider installing bats for testing"
	@command -v bc >/dev/null 2>&1 || echo "Consider installing bc for calculations"

.PHONY: setup-dev
setup-dev: install-deps
	@echo "Setting up development environment..."
	@mkdir -p $(BUILD_DIR) $(DIST_DIR)
	@echo "Development environment ready!"

# Clean targets
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@rm -f *.log

.PHONY: distclean
distclean: clean
	@echo "Deep cleaning..."
	@rm -rf cache/ tmp/ temp/

# Version info
.PHONY: version
version:
	@echo "Template: $(TEMPLATE_NAME)"
	@echo "Version: $(VERSION)"

# Validate configuration
.PHONY: validate-config
validate-config:
	@echo "Validating configuration files..."
	@if [ -f $(CONFIG_DIR)/template.yaml ]; then \
		echo "Configuration file found"; \
	else \
		echo "Warning: Configuration file not found"; \
	fi