#!/bin/bash

# Test runner script for better-cppexporter BATS test suite

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    local color="$1"
    local message="$2"
    printf "${color}%s${NC}\n" "$message"
}

print_header() {
    echo
    print_status "$BLUE" "================================================================"
    print_status "$BLUE" "$1"
    print_status "$BLUE" "================================================================"
    echo
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_deps=()
    
    # Check for BATS
    if ! command -v bats >/dev/null 2>&1; then
        missing_deps+=("bats")
    else
        print_status "$GREEN" "✓ BATS is installed: $(bats --version)"
    fi
    
    # Check for Ghidra
    if [[ -z "$GHIDRA_INSTALL_DIR" ]]; then
        print_status "$YELLOW" "⚠ GHIDRA_INSTALL_DIR not set, will try to detect automatically"
    else
        if [[ -f "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]]; then
            print_status "$GREEN" "✓ Ghidra found at: $GHIDRA_INSTALL_DIR"
        else
            missing_deps+=("ghidra (invalid GHIDRA_INSTALL_DIR)")
        fi
    fi
    
    # Check for test binary
    if [[ -f "$PROJECT_ROOT/examples/ls" ]]; then
        print_status "$GREEN" "✓ Test binary found: $PROJECT_ROOT/examples/ls"
    else
        print_status "$YELLOW" "⚠ Test binary not found, some tests may be skipped"
    fi
    
    # Check for required tools
    for tool in gcc timeout; do
        if command -v "$tool" >/dev/null 2>&1; then
            print_status "$GREEN" "✓ $tool is available"
        else
            missing_deps+=("$tool")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_status "$RED" "✗ Missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            print_status "$RED" "  - $dep"
        done
        echo
        print_status "$YELLOW" "Install missing dependencies and retry"
        return 1
    fi
    
    print_status "$GREEN" "All prerequisites satisfied!"
    return 0
}

# Run a specific test suite
run_test_suite() {
    local test_file="$1"
    local test_name="$(basename "$test_file" .bats)"
    
    print_header "Running $test_name"
    
    if [[ ! -f "$test_file" ]]; then
        print_status "$RED" "✗ Test file not found: $test_file"
        return 1
    fi
    
    # Run the tests
    local start_time end_time duration
    start_time=$(date +%s)
    
    # Build bats command with optional parallel jobs
    local bats_cmd="bats --tap"
    if [[ -n "$JOBS" && "$JOBS" -gt 1 ]]; then
        bats_cmd="$bats_cmd --jobs \"$JOBS\""
    fi
    if [[ "$NO_TEMPDIR_CLEANUP" == "true" ]]; then
        bats_cmd="$bats_cmd --no-tempdir-cleanup"
    fi
    bats_cmd="$bats_cmd \"$test_file\""
    
    if eval "$bats_cmd"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        print_status "$GREEN" "✓ $test_name completed successfully in ${duration}s"
        return 0
    else
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        print_status "$RED" "✗ $test_name failed after ${duration}s"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_SUITES...]

Run BATS test suites for better-cppexporter

OPTIONS:
    -h, --help              Show this help message
    -c, --check             Only check prerequisites, don't run tests
    -v, --verbose           Enable verbose output
    --jobs N                Run tests within each suite in parallel (N = number of jobs)
    --no-tempdir-cleanup    Don't clean up temporary directories after tests (useful for debugging)

TEST_SUITES:
    basic                   Basic functionality tests
    advanced                Advanced feature tests  
    validation              Output validation tests
    error                   Error handling tests
    recompilation           Function recompilation tests
    all                     Run all test suites (default)

EXAMPLES:
    $0                      # Run all tests
    $0 basic advanced       # Run only basic and advanced tests
    $0 --check              # Check prerequisites only
    $0 --jobs 4             # Run tests within each suite using 4 parallel jobs

ENVIRONMENT VARIABLES:
    GHIDRA_INSTALL_DIR     Path to Ghidra installation directory
    BATS_TEST_TIMEOUT      Timeout for individual tests (default: 300s)
    BATS_PARALLEL_JOBS     Default number of parallel jobs (overridden by --jobs)

EOF
}

# Parse command line arguments
parse_args() {
    local args=()
    local check_only=false
    local verbose=false
    local jobs=""
    local no_tempdir_cleanup=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --jobs)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    jobs="$2"
                    shift 2
                else
                    print_status "$RED" "Error: --jobs requires a numeric argument"
                    exit 1
                fi
                ;;
            --no-tempdir-cleanup)
                no_tempdir_cleanup=true
                shift
                ;;
            -*)
                print_status "$RED" "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Set global variables
    CHECK_ONLY="$check_only"
    VERBOSE="$verbose"
    JOBS="$jobs"
    NO_TEMPDIR_CLEANUP="$no_tempdir_cleanup"
    TEST_SUITES=("${args[@]}")
    
    # Use environment variable as default for jobs if not specified
    if [[ -z "$JOBS" && -n "$BATS_PARALLEL_JOBS" ]]; then
        JOBS="$BATS_PARALLEL_JOBS"
    fi
    
    # Default to all tests if none specified
    if [[ ${#TEST_SUITES[@]} -eq 0 ]]; then
        TEST_SUITES=("all")
    fi
}

# Main execution
main() {
    local script_start_time end_time total_duration
    script_start_time=$(date +%s)
    
    parse_args "$@"
    
    print_header "Better C++ Exporter Test Suite"
    print_status "$BLUE" "Project: $PROJECT_ROOT"
    print_status "$BLUE" "Tests: $TEST_DIR"
    echo
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Handle check-only mode
    if [[ "$CHECK_ONLY" == "true" ]]; then
        print_status "$GREEN" "Prerequisites check passed!"
        exit 0
    fi
    
    # Determine which test files to run
    local test_files=()
    for suite in "${TEST_SUITES[@]}"; do
        case "$suite" in
            basic)
                test_files+=("$TEST_DIR/basic_tests.bats")
                ;;
            advanced)
                test_files+=("$TEST_DIR/advanced_tests.bats")
                ;;
            validation)
                test_files+=("$TEST_DIR/validation_tests.bats")
                ;;
            error)
                test_files+=("$TEST_DIR/error_tests.bats")
                ;;
            recompilation)
                test_files+=("$TEST_DIR/recompilation_tests.bats")
                ;;
            all)
                test_files=(
                    "$TEST_DIR/basic_tests.bats"
                    "$TEST_DIR/advanced_tests.bats"
                    "$TEST_DIR/validation_tests.bats"
                    "$TEST_DIR/error_tests.bats"
                    "$TEST_DIR/recompilation_tests.bats"
                )
                break
                ;;
            *)
                print_status "$RED" "Unknown test suite: $suite"
                exit 1
                ;;
        esac
    done
    
    # Run the tests
    local failed_tests=()
    local passed_tests=()
    
    print_header "Running Test Suites"
    
    for test_file in "${test_files[@]}"; do
        if run_test_suite "$test_file"; then
            passed_tests+=("$(basename "$test_file" .bats)")
        else
            failed_tests+=("$(basename "$test_file" .bats)")
        fi
        echo
    done
    
    # Report results
    end_time=$(date +%s)
    total_duration=$((end_time - script_start_time))
    
    print_header "Test Results Summary"
    
    if [[ ${#passed_tests[@]} -gt 0 ]]; then
        print_status "$GREEN" "✓ Passed test suites (${#passed_tests[@]}):"
        for test in "${passed_tests[@]}"; do
            print_status "$GREEN" "  - $test"
        done
    fi
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        print_status "$RED" "✗ Failed test suites (${#failed_tests[@]}):"
        for test in "${failed_tests[@]}"; do
            print_status "$RED" "  - $test"
        done
    fi
    
    echo
    print_status "$BLUE" "Total runtime: ${total_duration}s"
    
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        print_status "$GREEN" "🎉 All test suites passed!"
        exit 0
    else
        print_status "$RED" "❌ ${#failed_tests[@]} test suite(s) failed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
