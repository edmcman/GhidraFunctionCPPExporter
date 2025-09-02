#!/bin/bash

# =============================================================================
# Better C/C++ Exporter for Ghidra - Simple Frontend
# =============================================================================
#
# A simple bash frontend for the better-cppexporter Ghidra script.
# This script provides an easy way to export decompiled C/C++ code from
# binary files using Ghidra's headless analysis.
#
# Usage:
#   ./export.bash <binary_file> [ghidra_args...]
#
# Examples:
#   ./export.bash /path/to/binary                              # Basic export
#   ./export.bash ./examples/ls                                # Export ls binary
#   ./export.bash binary.exe address_set_str "0x1124c0"       # With additional args
#
# The script will:
# 1. Create a temporary Ghidra project
# 2. Import the binary file
# 3. Run auto-analysis
# 4. Export decompiled C code
# 5. Clean up the temporary project
#
# Any additional arguments after the binary file will be forwarded to analyzeHeadless.
# Output files will be created in the current directory by default.
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function for temporary project
cleanup_temp_project() {
    local temp_dir="$1"
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        print_info "Cleaning up temporary project directory: $temp_dir"
        rm -rf "$temp_dir"
    fi
}

# Check if Ghidra is installed and GHIDRA_INSTALL_DIR is set
check_ghidra() {
    if [ -z "$GHIDRA_INSTALL_DIR" ]; then
        print_error "GHIDRA_INSTALL_DIR environment variable is not set"
        print_info "Please set it to your Ghidra installation directory, e.g.:"
        print_info "export GHIDRA_INSTALL_DIR=/path/to/ghidra"
        exit 1
    fi
    
    if [ ! -f "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]; then
        print_error "Ghidra analyzeHeadless not found at: $GHIDRA_INSTALL_DIR/support/analyzeHeadless"
        print_info "Please check your GHIDRA_INSTALL_DIR setting"
        exit 1
    fi
    
    print_info "Using Ghidra at: $GHIDRA_INSTALL_DIR"
}

# Show usage information
show_usage() {
    echo "Usage: $0 <binary_file> [ghidra_args...]"
    echo ""
    echo "Arguments:"
    echo "  binary_file    Path to the binary file to analyze"
    echo "  ghidra_args... Additional arguments to pass to Ghidra's analyzeHeadless"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/binary"
    echo "  $0 ./examples/ls"
    echo "  $0 binary.exe address_set_str \"0x1124c0\""
    echo ""
    echo "Environment Variables:"
    echo "  GHIDRA_INSTALL_DIR  Path to Ghidra installation (required)"
    echo ""
    echo "The exported C files will be created in the current directory."
    echo "A temporary Ghidra project will be created and cleaned up automatically."
}

# Main function
main() {
    # Check arguments
    if [ $# -lt 1 ]; then
        print_error "Missing required argument: binary_file"
        echo ""
        show_usage
        exit 1
    fi
    
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    # Parse arguments
    BINARY_FILE="$1"
    shift  # Remove binary file from arguments, rest will be forwarded to Ghidra
    
    # Check if output_dir and base_name are specified in the arguments
    OUTPUT_DIR="."
    CUSTOM_BASENAME=""
    args=("$@")
    
    # Prepare arguments for the Python script and parse output_dir/base_name
    ghidra_args=()
    skip_next=false
    for ((i=0; i<${#args[@]}; i++)); do
        if [ "$skip_next" = true ]; then
            skip_next=false
            continue
        fi
        
        if [[ "${args[i]}" == "base_name" ]] && [[ $((i+1)) -lt ${#args[@]} ]]; then
            CUSTOM_BASENAME="${args[i+1]}"
            skip_next=true
        elif [[ "${args[i]}" == "output_dir" ]] && [[ $((i+1)) -lt ${#args[@]} ]]; then
            OUTPUT_DIR="${args[i+1]}"
            skip_next=true
        else
            ghidra_args+=("${args[i]}")
        fi
    done
    
    # Always pass OUTPUT_BASENAME and OUTPUT_DIR to Ghidra
    ghidra_args+=("base_name" "$OUTPUT_BASENAME" "output_dir" "$OUTPUT_DIR")
    
    # Validate binary file
    if [ ! -f "$BINARY_FILE" ]; then
        print_error "Binary file not found: $BINARY_FILE"
        exit 1
    fi
    
    # Get absolute path of binary file
    BINARY_FILE=$(realpath "$BINARY_FILE")
    print_info "Binary file: $BINARY_FILE"
    
    # Check Ghidra installation
    check_ghidra
    
    # Get absolute path of the exporter script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    EXPORTER_SCRIPT="$SCRIPT_DIR/cpp_exporter_headless.py"
    
    if [ ! -f "$EXPORTER_SCRIPT" ]; then
        print_error "Exporter script not found: $EXPORTER_SCRIPT"
        exit 1
    fi
    
    # Create temporary project directory
    TEMP_PROJECT_DIR=$(mktemp -d -t ghidra_project_XXXXXX)
    PROJECT_NAME="temp_export"
    
    # Set up cleanup trap
    trap 'cleanup_temp_project "$TEMP_PROJECT_DIR"' EXIT
    
    print_info "Using temporary project directory: $TEMP_PROJECT_DIR"
    print_info "Project name: $PROJECT_NAME"
    
    # Get the base name of the binary for the output
    BINARY_NAME=$(basename "$BINARY_FILE")
    
    # Use custom basename if provided, otherwise use the binary name
    if [ -n "$CUSTOM_BASENAME" ]; then
        OUTPUT_BASENAME="$CUSTOM_BASENAME"
        print_info "Using custom basename: $OUTPUT_BASENAME"
    else
        OUTPUT_BASENAME="${BINARY_NAME%.exe}"
        print_info "Output will be based on: $BINARY_NAME"
    fi
    
    # Always pass OUTPUT_BASENAME and OUTPUT_DIR to Ghidra
    ghidra_args+=("base_name" "$OUTPUT_BASENAME" "output_dir" "$OUTPUT_DIR")
    
    print_info "Starting Ghidra headless analysis..."
    print_warning "This may take a while depending on the size of the binary..."
    
    # Run Ghidra headless analysis with corrected arguments
    "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" \
        "$TEMP_PROJECT_DIR" \
        "$PROJECT_NAME" \
        -import "$BINARY_FILE" \
        -preScript "$EXPORTER_SCRIPT" \
        "${ghidra_args[@]}"
    
    # Check if output files were created
    C_FILE="$OUTPUT_DIR/${OUTPUT_BASENAME}.c"
    if [ -f "$C_FILE" ]; then
        print_success "C file created: $C_FILE"
    else
        print_error "No C file found. Check the Ghidra output above for errors."
        print_error "$C_FILE"
        exit 1
    fi
    
    H_FILE="$OUTPUT_DIR/${OUTPUT_BASENAME}.h"
    if [ -f "$H_FILE" ]; then
        print_success "Header file created: $H_FILE"
    fi
    
    print_success "Export completed!"
    print_info "You can now compile individual functions from the exported C file."
    print_info "Temporary project will be cleaned up automatically."
}

# Run main function
main "$@"
