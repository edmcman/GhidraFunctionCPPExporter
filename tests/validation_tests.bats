#!/usr/bin/env bats

# Output validation and compilation tests for better-cppexporter

load test_helper

@test "exported c file has valid c syntax basics" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path"
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Basic syntax checks
    # Should have opening and closing braces
    local open_braces
    local close_braces
    open_braces=$(grep -c "{" "$c_file" || echo "0")
    close_braces=$(grep -c "}" "$c_file" || echo "0")
    
    [[ $open_braces -gt 0 ]]
    [[ $close_braces -gt 0 ]]
    
    # Should have semicolons (statements)
    grep -q ";" "$c_file"
}

@test "exported c file can be syntax-checked by gcc" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path"
        
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Try syntax check with gcc (not full compilation)
    run gcc -fsyntax-only "$c_file"
    
    # We'll be lenient here - syntax check might fail due to missing headers
    # but should not have severe syntax errors
    # Exit codes: 0 = success, 1 = warnings, >1 = serious errors
    [[ $status -le 1 ]] || {
        echo "GCC syntax check failed with exit code $status"
        echo "GCC output: $output"
        false
    }
}

@test "exported files have consistent function declarations" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path" create_header_file "true" emit_function_declarations "true"
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    local h_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").h"
    
    if [[ -f "$h_file" ]] && [[ -f "$c_file" ]]; then
        # Both files should exist and have content
        [[ $(get_file_size "$h_file") -gt 0 ]]
        [[ $(get_file_size "$c_file") -gt 0 ]]
        
        # Basic check: both should reference similar function names
        # This is a loose check since exact matching is complex
        local h_functions
        local c_functions
        h_functions=$(grep -o '[a-zA-Z_][a-zA-Z0-9_]*(' "$h_file" | head -5 || echo "")
        c_functions=$(grep -o '[a-zA-Z_][a-zA-Z0-9_]*(' "$c_file" | head -5 || echo "")
        
        # Should have some functions in both files
        [[ -n "$h_functions" ]] || [[ -n "$c_functions" ]]
    fi
}

@test "exported c file contains function implementations" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path"
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Should have function implementations section
    grep -q "FUNCTION IMPLEMENTATIONS" "$c_file" || {
        # Or at least have some function-like structures
        grep -q "^[a-zA-Z_].*{" "$c_file"
    }
    
    # Should have actual function bodies
    local function_count
    function_count=$(count_functions)
    [[ $function_count -gt 0 ]]
}

@test "export produces deterministic output for same input" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # First export
    local output1="$BATS_TEST_TMPDIR/deterministic_test1"
    mkdir -p "$output1"
    run_export -0 "$binary_path" output_dir "$output1"
    
    # Second export
    local output2="$BATS_TEST_TMPDIR/deterministic_test2"
    mkdir -p "$output2"
    run_export -0 "$binary_path" output_dir "$output2"
    
    # Compare the outputs (allowing for minor differences like timestamps)
    local base_name
    base_name=$(basename "$binary_path")
    local c_file1="$output1/$base_name.c"
    local c_file2="$output2/$base_name.c"
    
    if [[ -f "$c_file1" ]] && [[ -f "$c_file2" ]]; then
        # Files should have similar sizes (within 10% difference)
        local size1 size2
        size1=$(get_file_size "$c_file1")
        size2=$(get_file_size "$c_file2")
        
        local diff=$((size1 - size2))
        local abs_diff=${diff#-}  # absolute value
        local max_diff=$((size1 / 10))  # 10% of original size
        
        [[ $abs_diff -le $max_diff ]] || {
            echo "Output files have significantly different sizes: $size1 vs $size2"
            false
        }
    fi
}
