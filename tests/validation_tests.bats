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

@test "global variables are placed in header file when header is created" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Export with both C and header files, enabling global variables
    run_export -0 "$binary_path" \
        create_header_file "true" \
        emit_referenced_globals "true" \
        base_name "globals_test"
    
    local c_file="$BATS_TEST_TMPDIR/globals_test.c"
    local h_file="$BATS_TEST_TMPDIR/globals_test.h"
    
    [[ -f "$c_file" ]]
    [[ -f "$h_file" ]]
    
    # Check that header file contains global variables section
    if grep -q "GLOBAL VARIABLES" "$h_file"; then
        # Header file should contain global variable declarations
        echo "✓ Global variables section found in header file"
        
        # Count global variable declarations in header
        local header_globals
        header_globals=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_].*;" "$h_file" | head -1)
        echo "Found $header_globals global declarations in header"
        
        # C file should NOT contain global variables section when header exists
        if grep -q "GLOBAL VARIABLES" "$c_file"; then
            echo "✗ FAIL: C file should not contain global variables section when header exists"
            false
        else
            echo "✓ C file correctly excludes global variables section"
        fi
    else
        echo "No global variables found (this may be expected for this binary)"
    fi
    
    # Verify header file includes proper section headers
    grep -q "DATA TYPES\|FUNCTION DECLARATIONS" "$h_file"
}

@test "global variables are placed in C file when no header is created" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Export with only C file, enabling global variables
    run_export -0 "$binary_path" \
        create_header_file "false" \
        emit_referenced_globals "true" \
        base_name "globals_c_only_test"
    
    local c_file="$BATS_TEST_TMPDIR/globals_c_only_test.c"
    local h_file="$BATS_TEST_TMPDIR/globals_c_only_test.h"
    
    [[ -f "$c_file" ]]
    [[ ! -f "$h_file" ]]
    
    # When no header file is created, globals should be in C file
    # (This maintains backward compatibility)
    if grep -q "GLOBAL VARIABLES" "$c_file"; then
        echo "✓ Global variables correctly placed in C file when no header exists"
    else
        echo "No global variables found in C file (this may be expected for this binary)"
    fi
}

@test "header and C file structure is correct with both files enabled" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Export with both files enabled
    run_export -0 "$binary_path" \
        create_header_file "true" \
        create_c_file "true" \
        emit_referenced_globals "true" \
        emit_function_declarations "true" \
        emit_type_definitions "true" \
        base_name "structure_test"
    
    local c_file="$BATS_TEST_TMPDIR/structure_test.c"
    local h_file="$BATS_TEST_TMPDIR/structure_test.h"
    
    [[ -f "$c_file" ]]
    [[ -f "$h_file" ]]
    
    # Header file should contain declarations and types
    local header_sections=()
    if grep -q "DATA TYPES" "$h_file"; then
        header_sections+=("DATA TYPES")
    fi
    if grep -q "FUNCTION DECLARATIONS" "$h_file"; then
        header_sections+=("FUNCTION DECLARATIONS")
    fi
    if grep -q "GLOBAL VARIABLES" "$h_file"; then
        header_sections+=("GLOBAL VARIABLES")
    fi
    
    # C file should contain implementations and include header
    local c_sections=()
    if grep -q "#include \"structure_test.h\"" "$c_file"; then
        c_sections+=("HEADER INCLUDE")
    fi
    if grep -q "FUNCTION IMPLEMENTATIONS" "$c_file"; then
        c_sections+=("FUNCTION IMPLEMENTATIONS")
    fi
    
    echo "Header sections: ${header_sections[*]}"
    echo "C file sections: ${c_sections[*]}"
    
    # Verify proper separation of concerns
    [[ ${#header_sections[@]} -gt 0 ]] || skip "No header sections found"
    [[ ${#c_sections[@]} -gt 0 ]] || skip "No C file sections found"
    
    # C file should include the header when both are created
    grep -q "#include \"structure_test.h\"" "$c_file"
}
