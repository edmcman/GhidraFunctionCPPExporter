#!/bin/bash

# BATS test helper functions for better-cppexporter

# Test configuration
export TEST_BINARY_DIR="${BATS_TEST_DIRNAME}/../examples"
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# Clean up function called after each test
teardown() {
    # Cleanup is handled automatically by BATS temporary directories
    true
}

# Setup function called before each test
setup() {
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

# Helper function to run the export script
run_export() {
    local binary_path="$1"
    shift
    local args=("$@")
    
    # Check if output_dir is specified in the arguments, otherwise use default
    local output_dir_specified=false
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "output_dir" ]] && [[ $((i+1)) -lt ${#args[@]} ]]; then
            output_dir_specified=true
            break
        fi
    done
    
    # If output_dir is not specified, add it with default value
    if [[ "$output_dir_specified" == false ]]; then
        args=("output_dir" "$BATS_TEST_TMPDIR" "${args[@]}")
    fi
    
    # Run the export script with parsed arguments
    "$PROJECT_ROOT/export.bash" "$binary_path" "${args[@]}"
    return $?
}

# Helper function to check if exported files exist
check_exported_files() {
    local output_dir="${1:-$BATS_TEST_TMPDIR}"
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
    local output_dir="${1:-$BATS_TEST_TMPDIR}"
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
    local output_dir="${1:-$BATS_TEST_TMPDIR}"
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
    local output_dir="${2:-$BATS_TEST_TMPDIR}"
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
    local output_dir="${1:-$BATS_TEST_TMPDIR}"
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
