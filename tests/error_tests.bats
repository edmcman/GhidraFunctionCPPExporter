#!/usr/bin/env bats

# Error handling and edge case tests for better-cppexporter

load test_helper

@test "export handles corrupted binary gracefully" {
    # Create a corrupted binary file
    local corrupted_binary="$TEST_OUTPUT_DIR/corrupted_binary"
    dd if=/dev/urandom of="$corrupted_binary" bs=1024 count=1 2>/dev/null
    chmod +x "$corrupted_binary"
    
    # Try to export it - should not crash
    run_export "$corrupted_binary"
    
    # Should either succeed with warnings or fail gracefully
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]] || [[ $status -eq 2 ]]
}

@test "export handles binary with no functions" {
    # Create a minimal binary with no functions
    local minimal_binary="$TEST_OUTPUT_DIR/minimal_binary"
    echo -ne '\x7fELF' > "$minimal_binary"  # Basic ELF header start
    chmod +x "$minimal_binary"
    
    run_export "$minimal_binary"
    
    # Should handle gracefully
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]] || [[ $status -eq 2 ]]
}

@test "export handles very long function names" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Test with a very long function name filter
    local long_name
    long_name=$(printf 'a%.0s' {1..1000})  # 1000 character function name
    
    run_export "$binary_path" include_functions_only "$long_name"
    
    # Should not crash
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
}

@test "export handles special characters in output path" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Create output directory with special characters
    local special_output="$TEST_OUTPUT_DIR/test with spaces & symbols!"
    mkdir -p "$special_output"
    
    timeout "$BATS_TEST_TIMEOUT" "$PROJECT_ROOT/export.bash" "$binary_path" output_dir "$special_output"
    local exit_code=$?
    
    # Should handle gracefully
    [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]]
    
    export LAST_TEST_OUTPUT="$special_output"
}

@test "export handles read-only output directory" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Create read-only directory
    local readonly_output="$TEST_OUTPUT_DIR/readonly_dir"
    mkdir -p "$readonly_output"
    chmod 444 "$readonly_output"
    
    # Should fail gracefully when trying to write to read-only directory
    run timeout "$BATS_TEST_TIMEOUT" "$PROJECT_ROOT/export.bash" "$binary_path" output_dir "$readonly_output"
    
    # Should fail but not crash
    [[ $status -ne 0 ]]
    
    # Restore permissions for cleanup
    chmod 755 "$readonly_output" 2>/dev/null || true
}

@test "export handles missing ghidra installation" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Temporarily set invalid Ghidra path
    local original_ghidra="$GHIDRA_INSTALL_DIR"
    export GHIDRA_INSTALL_DIR="/nonexistent/ghidra"
    
    run timeout "$BATS_TEST_TIMEOUT" "$PROJECT_ROOT/export.bash" "$binary_path"
    local exit_code=$status
    
    # Restore original Ghidra path
    export GHIDRA_INSTALL_DIR="$original_ghidra"
    
    # Should fail with appropriate error
    [[ $exit_code -ne 0 ]]
    [[ "$output" =~ "Ghidra" ]] || [[ "$output" =~ "not found" ]]
}

@test "export handles extremely large address ranges" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Use maximum possible address range
    run_export "$binary_path" address_set_str "0x0-0xffffffffffffffff"
    
    # Should either process successfully or fail gracefully
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]] || [[ $status -eq 2 ]]
}

@test "export handles invalid function tag syntax" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Use invalid tag syntax
    run_export "$binary_path" function_tag_filters "invalid,tag,with,special!@#$%^&*()characters"
    
    # Should handle gracefully
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
}

@test "export handles multiple conflicting options" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Use conflicting options
    run_export "$binary_path" \
        create_c_file "false" \
        create_header_file "false" \
        emit_function_declarations "true"
    
    # Should either create at least one output file or fail gracefully
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
}

@test "export handles disk space exhaustion simulation" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Create a filesystem with limited space (using tmpfs)
    local limited_fs="$TEST_OUTPUT_DIR/limited_space"
    mkdir -p "$limited_fs"
    
    # Try to mount a small tmpfs (this might fail if not root, which is fine)
    if mount -t tmpfs -o size=1M tmpfs "$limited_fs" 2>/dev/null; then
        # Fill most of the space
        dd if=/dev/zero of="$limited_fs/filler" bs=1024 count=900 2>/dev/null || true
        
        # Try export
        run timeout "$BATS_TEST_TIMEOUT" "$PROJECT_ROOT/export.bash" "$binary_path" output_dir "$limited_fs"
        local exit_code=$status
        
        # Clean up
        umount "$limited_fs" 2>/dev/null || true
        
        # Should handle disk full gracefully
        [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]] || [[ $exit_code -eq 2 ]]
    else
        # Skip if we can't create tmpfs (no root privileges)
        skip "Cannot create tmpfs (requires root privileges)"
    fi
}

@test "export handles unicode characters in binary name" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Copy binary with unicode name
    local unicode_binary="$TEST_OUTPUT_DIR/test_binary_🚀_测试.bin"
    cp "$binary_path" "$unicode_binary"
    chmod +x "$unicode_binary"
    
    run_export "$unicode_binary"
    
    # Should handle unicode filenames gracefully
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
}

@test "export handles simultaneous access to same binary" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Start multiple exports of the same binary simultaneously
    local pids=()
    local outputs=()
    
    for i in {1..2}; do
        local output_dir="$TEST_OUTPUT_DIR/simultaneous_test_$i"
        mkdir -p "$output_dir"
        outputs+=("$output_dir")
        
        (
            timeout "$BATS_TEST_TIMEOUT" "$PROJECT_ROOT/export.bash" "$binary_path" output_dir "$output_dir"
        ) &
        pids+=($!)
    done
    
    # Wait for processes and collect results
    local success_count=0
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success_count++))
        fi
    done
    
    # At least one should succeed
    [[ $success_count -gt 0 ]]
}

@test "export handles malformed command line arguments" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Test various malformed argument patterns
    local malformed_args=(
        "create_c_file"  # Missing value
        "output_dir \"unterminated_quote"  # Unterminated quote
        "address_set_str \"\""  # Empty quoted value
        "emit_function_declarations maybe"  # Invalid boolean
    )
    
    for args in "${malformed_args[@]}"; do
        run timeout 30 "$PROJECT_ROOT/export.bash" "$binary_path" $args
        # Should not hang or crash
        [[ $status -ne 124 ]]  # 124 is timeout exit code
    done
}
