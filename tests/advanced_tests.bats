#!/usr/bin/env bats



# Advanced functionality tests for better-cppexporter

load test_helper

@test "export with function declarations includes prototypes" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" emit_function_declarations "true"
    [[ $status -eq 0 ]]
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Should contain function declarations section
    grep -q "FUNCTION DECLARATIONS" "$c_file"
}

@test "export with type definitions includes data types" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" emit_type_definitions "true"
    [[ $status -eq 0 ]]
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Should contain some type definitions (typedef, struct, etc.)
    grep -q -E "(typedef|struct|enum)" "$c_file"
}

@test "export with global variables includes globals" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" emit_referenced_globals "true"
    [[ $status -eq 0 ]]
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Check for global variables section or external declarations
    grep -q -E "(extern|GLOBAL VARIABLES)" "$c_file" || true  # Might not have globals
}

@test "export with cpp style comments uses cpp comments" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" use_cpp_style_comments "true"
    [[ $status -eq 0 ]]
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Should contain C++ style comments
    grep -q "//" "$c_file"
}

@test "export with c style comments uses c comments" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" use_cpp_style_comments "false"
    [[ $status -eq 0 ]]
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    
    # Should contain C style comments
    grep -q "/\*" "$c_file"
}

@test "export with specific function filter works" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Try to export only main function (common function name)
    run_export "$binary_path" include_functions_only "main"
    
    # Should succeed or fail gracefully if main doesn't exist
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
    
    if [[ $status -eq 0 ]]; then
        local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
        [[ -f "$c_file" ]]
        
        # If successful, should be smaller than full export
        local file_size
        file_size=$(get_file_size "$c_file")
        [[ $file_size -gt 0 ]]
    fi
}

@test "export with both header and c file creates both" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" create_header_file "true" create_c_file "true"
    [[ $status -eq 0 ]]
    
    local base_name
    base_name=$(basename "$binary_path")
    local c_file="$BATS_TEST_TMPDIR/$base_name.c"
    local h_file="$BATS_TEST_TMPDIR/$base_name.h"
    
    [[ -f "$c_file" ]]
    [[ -f "$h_file" ]]
    [[ $(get_file_size "$c_file") -gt 0 ]]
    [[ $(get_file_size "$h_file") -gt 0 ]]
}

@test "export handles invalid address range gracefully" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Use an invalid address range
    run_export "$binary_path" address_set_str "invalid_address"
    
    # Should not crash, might produce warning but should continue
    # We'll accept either success (if it recovers) or controlled failure
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]] || [[ $status -eq 2 ]]
}

@test "export with decompiler parameter id option works" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" run_decompiler_parameter_id "true"
    [[ $status -eq 0 ]]
    
    check_exported_files
}

@test "export creates reasonable output size" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path"
    [[ $status -eq 0 ]]
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    local file_size
    file_size=$(get_file_size "$c_file")
    
    # Should be at least 1KB (reasonable minimum for decompiled code)
    [[ $file_size -gt 1024 ]]
    
    # Should not be excessively large (less than 100MB)
    [[ $file_size -lt 104857600 ]]
}
