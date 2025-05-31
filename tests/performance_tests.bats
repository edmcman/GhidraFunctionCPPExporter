#!/usr/bin/env bats

# Performance and stress tests for better-cppexporter

load test_helper

@test "export completes within reasonable time" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Measure execution time
    local start_time end_time duration
    start_time=$(date +%s)
    
    run_export "$binary_path"
    [[ $status -eq 0 ]]
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Should complete within 5 minutes (300 seconds)
    [[ $duration -lt 300 ]] || {
        echo "Export took too long: ${duration} seconds"
        false
    }
    
    echo "Export completed in ${duration} seconds"
}

@test "export handles multiple concurrent runs" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Start multiple exports in parallel
    local pids=()
    local outputs=()
    
    for i in {1..3}; do
        local output_dir="$BATS_TEST_TMPDIR/concurrent_test_$i"
        mkdir -p "$output_dir"
        outputs+=("$output_dir")
        
        (
            run_export "$binary_path" output_dir "$output_dir"
        ) &
        pids+=($!)
    done
    
    # Wait for all processes to complete
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done
    
    [[ "$all_success" == "true" ]]
    
    # Check that all outputs were created
    for output_dir in "${outputs[@]}"; do
        local c_file="$output_dir/$(basename "$binary_path").c"
        [[ -f "$c_file" ]]
        [[ $(get_file_size "$c_file") -gt 0 ]]
    done
}

@test "export handles large address ranges efficiently" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Use a large address range
    local start_time end_time duration
    start_time=$(date +%s)
    
    run_export "$binary_path" address_set_str "0x0-0xffffffff"
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Should either succeed quickly or fail gracefully
    # Large address ranges might be filtered out by Ghidra
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
    
    # Should not take excessively long even for large ranges
    [[ $duration -lt 600 ]] || {
        echo "Large address range export took too long: ${duration} seconds"
        false
    }
}

@test "export memory usage stays reasonable" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Start the export in background and monitor memory
    run_export "$binary_path" &
    local export_pid=$!
    
    local max_memory=0
    while kill -0 "$export_pid" 2>/dev/null; do
        # Get memory usage of the process tree
        local memory_kb
        memory_kb=$(ps -o rss= -p "$export_pid" 2>/dev/null | awk '{sum += $1} END {print sum}' || echo "0")
        
        if [[ $memory_kb -gt $max_memory ]]; then
            max_memory=$memory_kb
        fi
        
        sleep 1
    done
    
    # Wait for the export to complete
    wait "$export_pid"
    local exit_code=$?
    
    [[ $exit_code -eq 0 ]]
    
    # Memory usage should be reasonable (less than 8GB = 8388608 KB)
    [[ $max_memory -lt 8388608 ]] || {
        echo "Export used too much memory: ${max_memory} KB"
        false
    }
    
    echo "Peak memory usage: ${max_memory} KB"
}

@test "export cleans up temporary files" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Count temporary files before export
    local temp_before
    temp_before=$(find /tmp -name "*ghidra*" -o -name "*better-cppexporter*" 2>/dev/null | wc -l)
    
    run_export "$binary_path"
    [[ $status -eq 0 ]]
    
    # Wait a bit for cleanup
    sleep 2
    
    # Count temporary files after export
    local temp_after
    temp_after=$(find /tmp -name "*ghidra*" -o -name "*better-cppexporter*" 2>/dev/null | wc -l)
    
    # Should not have significantly more temporary files
    local temp_diff=$((temp_after - temp_before))
    [[ $temp_diff -le 1 ]] || {
        echo "Too many temporary files left behind: $temp_diff"
        find /tmp -name "*ghidra*" -o -name "*better-cppexporter*" 2>/dev/null || true
        false
    }
}

@test "export handles interrupted execution gracefully" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    # Start export and interrupt it after a short time
    timeout 10 run_export "$binary_path" &
    local export_pid=$!
    
    # Let it run for a bit
    sleep 5
    
    # Interrupt the process
    kill -TERM "$export_pid" 2>/dev/null || true
    
    # Wait for it to die
    wait "$export_pid" 2>/dev/null || true
    
    # Check that no zombie processes are left
    ! pgrep -f "better-cppexporter" >/dev/null
    ! pgrep -f "analyzeHeadless" >/dev/null
    
    # Temporary files should eventually be cleaned up
    sleep 2
    local temp_files
    temp_files=$(find /tmp -name "*ghidra*" -o -name "*better-cppexporter*" 2>/dev/null | wc -l)
    
    # Allow some temporary files but not excessive amounts
    [[ $temp_files -lt 10 ]]
}
