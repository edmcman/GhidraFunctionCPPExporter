#!/usr/bin/env bats

# Recompilation tests for better-cppexporter
# Tests that exported functions can be successfully recompiled

load test_helper

# Helper function to test the full compile → decompile → recompile workflow
test_function_recompilation() {
    local program_code="$1"
    local function_name="$2"
    local test_name="${3:-test_function}"
    
    # Automatically create test output directory
    create_test_output_dir "$test_name"
    local initial_output_dir="$LAST_TEST_OUTPUT"
    
    local test_source_file="$initial_output_dir/${test_name}_source.c"
    local test_binary="$initial_output_dir/${test_name}_binary"
    
    # Step 1: Create and compile the input program to a full binary
    cat > "$test_source_file" << EOF
$program_code
EOF
    
    run gcc -o "$test_binary" "$test_source_file" -std=c99 -g
    if [[ $status -ne 0 ]]; then
        echo "Initial compilation failed with output: $output"
        return 1
    fi
    
    # Verify the binary was created
    [[ -f "$test_binary" ]]
    [[ -x "$test_binary" ]]
    
    # Step 2: Decompile the binary using the export script with function filtering
    run_export "$test_binary" include_functions_only "$function_name"
    if [[ $status -ne 0 ]]; then
        echo "Decompilation failed"
        return 1
    fi
    
    # Now use the directory that run_export created (stored in LAST_TEST_OUTPUT)
    local decompiled_c_file="$LAST_TEST_OUTPUT/${test_name}_decompiled.c"
    local extracted_function_file="$LAST_TEST_OUTPUT/${test_name}_function.c"
    local test_object="$LAST_TEST_OUTPUT/${test_name}_function.o"
    
    # The decompiled file should be in LAST_TEST_OUTPUT
    local decompiled_file="$LAST_TEST_OUTPUT/$(basename "$test_binary").c"
    [[ -f "$decompiled_file" ]]
    
    # Step 3: Use the exported function directly (no manual extraction needed)
    # The export script with include_functions_only already filtered to just our function
    # Copy the filtered output to our extracted function file
    cp "$decompiled_file" "$extracted_function_file"
    # Step 4: Try to compile the extracted function to object file
    run gcc -c -o "$test_object" "$extracted_function_file" -std=c99 -Wall
    
    if [[ $status -ne 0 ]]; then
        echo "Recompilation of extracted function failed with output: $output"
        return 1
    fi
    
    # Verify the object file was created
    [[ -f "$test_object" ]]
    
    # Verify it's actually an object file (has some content)
    [[ $(wc -c < "$test_object") -gt 0 ]]
    
    return 0
}

@test "simple hello world function can be recompiled" {
    local program=$(cat << 'EOF'
#include <stdio.h>
void hello() { printf("Hello world\n"); }
int main() { hello(); return 0; }
EOF
)
    
    test_function_recompilation "$program" "hello"
}

@test "function modifying global array can be recompiled" {
    local program=$(cat << 'EOF'
int arr[3] = {1, 2, 3};

void modify_array() {
    arr[0] = 42;
}

int main() {
    modify_array();
    return 0;
}
EOF
)
    
    test_function_recompilation "$program" "modify_array"
}
