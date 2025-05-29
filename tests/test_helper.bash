#!/bin/bash

# BATS test helper functions for better-cppexporter

# Test configuration
export BATS_TEST_TIMEOUT=300  # 5 minutes timeout for tests
export TEST_BINARY_DIR="${BATS_TEST_DIRNAME}/../examples"
export TEST_OUTPUT_DIR="${BATS_TEST_DIRNAME}/output"
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# Clean up function called after each test
teardown() {
    # Clean up any temporary files/directories created during tests
    if [[ -d "$TEST_OUTPUT_DIR" ]]; then
        rm -rf "$TEST_OUTPUT_DIR"
    fi
    
    # Clean up any temporary Ghidra projects
    if [[ -d ~/ghidra_projects ]]; then
        find ~/ghidra_projects -name "TestProject*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
}

# Setup function called before each test
setup() {
    # Create test output directory
    mkdir -p "$TEST_OUTPUT_DIR"
    
    # Ensure we have the required environment variables
    if [[ -z "$GHIDRA_INSTALL_DIR" ]]; then
        if [[ -d "/opt/ghidra" ]]; then
            export GHIDRA_INSTALL_DIR="/opt/ghidra"
        elif [[ -d "/usr/local/ghidra" ]]; then
            export GHIDRA_INSTALL_DIR="/usr/local/ghidra"
        else
            skip "GHIDRA_INSTALL_DIR environment variable not set and Ghidra not found in standard locations"
        fi
    fi
    
    # Verify Ghidra installation
    if [[ ! -d "$GHIDRA_INSTALL_DIR" ]]; then
        skip "Ghidra installation directory not found: $GHIDRA_INSTALL_DIR"
    fi
    
    if [[ ! -f "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]]; then
        skip "analyzeHeadless not found in Ghidra installation"
    fi
}

# Helper function to check if a binary exists for testing
check_test_binary() {
    local binary_name="$1"
    local binary_path="$TEST_BINARY_DIR/$binary_name"
    
    if [[ ! -f "$binary_path" ]]; then
        skip "Test binary not found: $binary_path"
    fi
    
    echo "$binary_path"
}

# Helper function to run the export script with timeout
run_export() {
    local binary_path="$1"
    shift
    local args=("$@")
    
    # Set output directory for this test
    local test_output="$TEST_OUTPUT_DIR/$(basename "$binary_path")_$(date +%s)"
    mkdir -p "$test_output"
    
    # Run the export script
    timeout "$BATS_TEST_TIMEOUT" "$PROJECT_ROOT/export.bash" "$binary_path" output_dir "$test_output" "${args[@]}"
    local exit_code=$?
    
    # Store the output directory for inspection
    export LAST_TEST_OUTPUT="$test_output"
    
    return $exit_code
}

# Helper function to check if exported files exist
check_exported_files() {
    local output_dir="${1:-$LAST_TEST_OUTPUT}"
    local base_name="${2:-$(basename "$TEST_BINARY_DIR/ls")}"
    
    local c_file="$output_dir/$base_name.c"
    local h_file="$output_dir/$base_name.h"
    
    # Check if at least one output file exists
    if [[ -f "$c_file" ]] || [[ -f "$h_file" ]]; then
        return 0
    else
        return 1
    fi
}

# Helper function to check if C file can be compiled
check_c_compilation() {
    local output_dir="${1:-$LAST_TEST_OUTPUT}"
    local base_name="${2:-$(basename "$TEST_BINARY_DIR/ls")}"
    
    local c_file="$output_dir/$base_name.c"
    local h_file="$output_dir/$base_name.h"
    
    if [[ ! -f "$c_file" ]]; then
        return 1
    fi
    
    # Try to compile the C file
    local compile_output="$output_dir/compile_test.o"
    
    # Basic compilation flags
    local compile_flags=("-c" "-o" "$compile_output")
    
    # Add header include if header file exists
    if [[ -f "$h_file" ]]; then
        compile_flags+=("-I" "$output_dir")
    fi
    
    # Attempt compilation
    gcc "${compile_flags[@]}" "$c_file" 2>"$output_dir/compile_errors.log"
    local exit_code=$?
    
    # Store compilation results
    export LAST_COMPILE_OUTPUT="$compile_output"
    export LAST_COMPILE_ERRORS="$output_dir/compile_errors.log"
    
    return $exit_code
}

# Helper function to count functions in exported C file
count_functions() {
    local output_dir="${1:-$LAST_TEST_OUTPUT}"
    local base_name="${2:-$(basename "$TEST_BINARY_DIR/ls")}"
    
    local c_file="$output_dir/$base_name.c"
    
    if [[ ! -f "$c_file" ]]; then
        echo "0"
        return
    fi
    
    # Count function definitions (lines that look like function definitions)
    grep -c '^[a-zA-Z_][a-zA-Z0-9_]*.*(' "$c_file" || echo "0"
}

# Helper function to check if specific function exists in output
function_exists() {
    local function_name="$1"
    local output_dir="${2:-$LAST_TEST_OUTPUT}"
    local base_name="${3:-$(basename "$TEST_BINARY_DIR/ls")}"
    
    local c_file="$output_dir/$base_name.c"
    
    if [[ ! -f "$c_file" ]]; then
        return 1
    fi
    
    grep -q "^.*$function_name.*(" "$c_file"
}

# Helper function to get file size
get_file_size() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        echo "0"
        return
    fi
    
    stat -c%s "$file_path"
}

# Helper function to validate that output contains expected sections
validate_output_structure() {
    local output_dir="${1:-$LAST_TEST_OUTPUT}"
    local base_name="${2:-$(basename "$TEST_BINARY_DIR/ls")}"
    
    local c_file="$output_dir/$base_name.c"
    local h_file="$output_dir/$base_name.h"
    
    local errors=()
    
    # Check C file structure if it exists
    if [[ -f "$c_file" ]]; then
        # Should have some function implementations
        if ! grep -q "FUNCTION IMPLEMENTATIONS" "$c_file"; then
            errors+=("C file missing function implementations section")
        fi
        
        # Should have valid C syntax (basic check)
        if ! grep -q "{" "$c_file"; then
            errors+=("C file appears to have no function bodies")
        fi
    fi
    
    # Check header file structure if it exists
    if [[ -f "$h_file" ]]; then
        # Should have some declarations or type definitions
        if ! grep -q -E "(typedef|struct|enum|extern)" "$h_file"; then
            errors+=("Header file appears to have no type definitions or declarations")
        fi
    fi
    
    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf "Output validation errors:\n"
        printf " - %s\n" "${errors[@]}"
        return 1
    fi
    
    return 0
}
