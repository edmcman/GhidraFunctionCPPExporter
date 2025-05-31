#!/usr/bin/env bats

# Basic functionality tests for better-cppexporter

load test_helper

@test "export script exists and is executable" {
    [[ -f "$PROJECT_ROOT/export.bash" ]]
    [[ -x "$PROJECT_ROOT/export.bash" ]]
}

@test "cpp_exporter_headless.py exists" {
    [[ -f "$PROJECT_ROOT/cpp_exporter_headless.py" ]]
}

@test "export script shows help when run without arguments" {
    run ! "$PROJECT_ROOT/export.bash"
    [[ "$output" =~ "Usage:" ]] || [[ "$output" =~ "binary_file" ]]
}

@test "export script fails gracefully with non-existent binary" {
    run ! "$PROJECT_ROOT/export.bash" "/nonexistent/binary"
}

@test "basic export with ls binary creates output files" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path"
    
    # Check that output files were created
    check_exported_files
}

@test "export creates C file with default settings" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path"
    
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    [[ $(get_file_size "$c_file") -gt 0 ]]
}

@test "export creates header file when requested" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path" create_header_file "true"
    
    local h_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").h"
    [[ -f "$h_file" ]]
    [[ $(get_file_size "$h_file") -gt 0 ]]
}

@test "exported C file has reasonable structure" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path"
    
    validate_output_structure
}

@test "export with custom base name works" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export -0 "$binary_path" base_name "test_export"
    
    local c_file="$BATS_TEST_TMPDIR/test_export.c"
    [[ -f "$c_file" ]]
}

@test "export with address filter produces smaller output" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # First, do a full export
    run_export -0 "$binary_path" base_name "full_export"
    
    local full_c_file="$BATS_TEST_TMPDIR/full_export.c"
    local full_size
    full_size=$(get_file_size "$full_c_file")
    
    # Then do a filtered export (using a specific address)
    run_export -0 "$binary_path" base_name "filtered_export" address_set_str "0x1000-0x2000"
    
    local filtered_c_file="$BATS_TEST_TMPDIR/filtered_export.c"
    local filtered_size
    filtered_size=$(get_file_size "$filtered_c_file")
    
    # Filtered export should be smaller (or at least not larger)
    [[ $filtered_size -le $full_size ]]
}

@test "export handles function tag filtering" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Test with a function tag filter (this might not find anything, but should not crash)
    run_export "$binary_path" function_tag_filters "IMPORTED"
    # Should not crash, even if no functions match
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
}
