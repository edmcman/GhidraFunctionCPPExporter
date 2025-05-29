# Makefile for better-cppexporter testing

# Configuration
SHELL := /bin/bash
TEST_DIR := tests
PROJECT_ROOT := .

# Default target
.PHONY: test
test: test-all

# Test targets
.PHONY: test-all test-basic test-advanced test-validation test-error
test-all:
	@echo "Running all tests..."
	@$(TEST_DIR)/run_tests.sh all

test-basic:
	@echo "Running basic tests..."
	@$(TEST_DIR)/run_tests.sh basic

test-advanced:
	@echo "Running advanced tests..."
	@$(TEST_DIR)/run_tests.sh advanced

test-validation:
	@echo "Running validation tests..."
	@$(TEST_DIR)/run_tests.sh validation

test-error:
	@echo "Running error handling tests..."
	@$(TEST_DIR)/run_tests.sh error

# Quick test (basic + advanced only)
.PHONY: test-quick
test-quick:
	@echo "Running quick tests..."
	@$(TEST_DIR)/run_tests.sh basic advanced

# Check prerequisites
.PHONY: test-check
test-check:
	@echo "Checking test prerequisites..."
	@$(TEST_DIR)/run_tests.sh --check

# Cleanup test artifacts
.PHONY: test-clean
test-clean:
	@echo "Cleaning test artifacts..."
	@$(TEST_DIR)/run_tests.sh --cleanup-only

# Help target
.PHONY: test-help
test-help:
	@echo "Available test targets:"
	@echo "  test, test-all      - Run all test suites"
	@echo "  test-basic          - Run basic functionality tests"
	@echo "  test-advanced       - Run advanced feature tests"
	@echo "  test-validation     - Run output validation tests"
	@echo "  test-error          - Run error handling tests"
	@echo "  test-quick          - Run basic and advanced tests only"
	@echo "  test-check          - Check test prerequisites"
	@echo "  test-clean          - Clean up test artifacts"
	@echo "  test-help           - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  GHIDRA_INSTALL_DIR  - Path to Ghidra installation"
	@echo "  BATS_TEST_TIMEOUT   - Test timeout in seconds (default: 300)"

# Install test dependencies (if running on a fresh system)
.PHONY: install-test-deps
install-test-deps:
	@echo "Installing test dependencies..."
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y bats gcc; \
	elif command -v yum >/dev/null 2>&1; then \
		sudo yum install -y bats gcc; \
	elif command -v pacman >/dev/null 2>&1; then \
		sudo pacman -S bats gcc; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install bats-core gcc; \
	else \
		echo "Please install bats and gcc manually"; \
		exit 1; \
	fi
