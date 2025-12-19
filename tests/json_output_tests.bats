#!/usr/bin/env bats

# JSON output tests for better-cppexporter

load test_helper

@test "JSON output comprehensive syntax and structure validation" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Export to JSON format (disable C and H files)
    run_export -0 "$binary_path" create_json_file "true" create_c_file "false" create_header_file "false"
    
    local json_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").json"
    
    # 1. File creation check
    [[ -f "$json_file" ]]
    [[ $(get_file_size "$json_file") -gt 0 ]]
    
    # 2. Valid JSON syntax check
    run -0 jq empty "$json_file"
    
    # 3. Required top-level fields present
    run -0 jq -e '.program_name' "$json_file"
    [[ "$output" =~ "ls" ]]
    
    run -0 jq -e '.header' "$json_file"
    run -0 jq -e '.functions' "$json_file"
    
    # 4. Functions are keyed by address (hex format)
    local first_func_key
    first_func_key=$(jq -r '.functions | keys[0]' "$json_file")
    [[ "$first_func_key" =~ ^[0-9a-fA-Fx]+$ ]]
    
    # 5. Each function has required fields with content
    run -0 jq -e ".functions[\"$first_func_key\"].name" "$json_file"
    [[ -n "$output" && "$output" != "null" ]]
    
    run -0 jq -e ".functions[\"$first_func_key\"].signature" "$json_file"
    [[ -n "$output" && "$output" != "null" ]]
    
    run -0 jq -e ".functions[\"$first_func_key\"].body" "$json_file"
    [[ -n "$output" && "$output" != "null" ]]
    
    # 6. Header field exists (may be empty or contain declarations/globals)
    local header_content
    header_content=$(jq -r '.header' "$json_file")
    # Just verify it's a string, content may be empty
    [[ "$header_content" != "null" ]]
    
    # 7. Functions field is not empty
    local func_count
    func_count=$(jq '.functions | length' "$json_file")
    [[ $func_count -gt 0 ]]
    
    # 8. Function bodies contain C code
    local func_body
    func_body=$(jq -r ".functions[\"$first_func_key\"].body" "$json_file")
    [[ "$func_body" =~ \{ ]]
    [[ "$func_body" =~ \} ]]
    
    # 9. JSON mode should not create C/H files
    local c_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").c"
    local h_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").h"
    [[ ! -f "$c_file" ]]
    [[ ! -f "$h_file" ]]
}

@test "JSON header contains all required section headers" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Export to JSON format with types enabled (no address filter to get full output)
    run_export -0 "$binary_path" \
        create_json_file "true" \
        create_c_file "false" \
        create_header_file "false" \
        emit_type_definitions "true"
    
    local json_file="$BATS_TEST_TMPDIR/$(basename "$binary_path").json"
    
    # Extract header content
    local header_content
    header_content=$(jq -r '.header' "$json_file")
    
    # Verify all section headers are present
    [[ "$header_content" =~ "DATA TYPES" ]]
    [[ "$header_content" =~ "FUNCTION DECLARATIONS" ]]
    [[ "$header_content" =~ "GLOBAL VARIABLES" ]]
    
    # EQUATES may not be present if binary has no equates, so don't check for it
    
    # Verify section header format (should have separator lines)
    [[ "$header_content" =~ "//==" ]] || [[ "$header_content" =~ "/*==" ]]
}
