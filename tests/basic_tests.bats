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
    run "$PROJECT_ROOT/export.bash"
    [[ $status -ne 0 ]]
    [[ "$output" =~ "Usage:" ]] || [[ "$output" =~ "binary_file" ]]
}

@test "export script fails gracefully with non-existent binary" {
    run "$PROJECT_ROOT/export.bash" "/nonexistent/binary"
    [[ $status -ne 0 ]]
}

@test "basic export with ls binary creates output files" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path"
    [[ $status -eq 0 ]]
    
    # Check that output files were created
    check_exported_files
}

@test "export creates C file with default settings" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path"
    [[ $status -eq 0 ]]
    
    local c_file="$LAST_TEST_OUTPUT/$(basename "$binary_path").c"
    [[ -f "$c_file" ]]
    [[ $(get_file_size "$c_file") -gt 0 ]]
}

@test "export creates header file when requested" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" create_header_file "true"
    [[ $status -eq 0 ]]
    
    local h_file="$LAST_TEST_OUTPUT/$(basename "$binary_path").h"
    [[ -f "$h_file" ]]
    [[ $(get_file_size "$h_file") -gt 0 ]]
}

@test "exported C file has reasonable structure" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path"
    [[ $status -eq 0 ]]
    
    validate_output_structure
}

@test "export with custom base name works" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path" base_name "test_export"
    [[ $status -eq 0 ]]
    
    local c_file="$LAST_TEST_OUTPUT/test_export.c"
    [[ -f "$c_file" ]]
}

@test "export with address filter produces smaller output" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # First, do a full export
    local full_output="$TEST_OUTPUT_DIR/full_export"
    mkdir -p "$full_output"
    
    timeout "$BATS_TEST_TIMEOUT" "$PROJECT_ROOT/export.bash" "$binary_path" output_dir "$full_output"
    [[ $? -eq 0 ]]
    
    local full_c_file="$full_output/$(basename "$binary_path").c"
    local full_size
    full_size=$(get_file_size "$full_c_file")
    
    # Then do a filtered export (using a specific address)
    run_export "$binary_path" address_set_str "0x1000-0x2000"
    [[ $status -eq 0 ]]
    
    local filtered_c_file="$LAST_TEST_OUTPUT/$(basename "$binary_path").c"
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
