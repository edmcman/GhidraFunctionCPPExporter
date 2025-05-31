# Better C++ Exporter - Test Framework

This directory contains a comprehensive BATS (Bash Automated Testing System) test framework for the better-cppexporter project.

## Overview

The test framework validates the functionality, performance, and output quality of the C++ exporter tool through automated tests.

## Test Structure

### Test Files

- **`basic_tests.bats`** - Basic functionality tests
  - Script existence and permissions
  - Help output
  - Basic export operations
  - Output file creation

- **`advanced_tests.bats`** - Advanced feature tests
  - Function declarations export
  - Type definitions export
  - Global variables export
  - Comment style options
  - Function filtering
  - Address range filtering

- **`validation_tests.bats`** - Output validation tests
  - C syntax validation
  - GCC syntax checking
  - Header file structure
  - Function declaration consistency
  - Output determinism

- **`error_tests.bats`** - Error handling and edge case tests
  - Corrupted binary handling
  - Invalid input handling
  - Error recovery testing
  - Edge case scenarios

- **`recompilation_tests.bats`** - Function recompilation tests
  - Full compile → decompile → recompile workflow testing
  - Validates that decompiled functions can be recompiled to object files
  - Tests round-trip compilation quality
  - Integration test for the entire toolchain

### Helper Files

- **`test_helper.bash`** - Shared functions and utilities
  - Test environment setup/teardown
  - Binary checking functions
  - Export execution helpers
  - Output validation functions
  - File size and compilation helpers

- **`run_tests.sh`** - Test runner script
  - Prerequisites checking
  - Test suite execution
  - Result reporting
  - Cleanup management

## Prerequisites

### Required Tools

- **BATS** - Bash Automated Testing System
- **Ghidra** - Binary analysis platform
- **GCC** - C compiler (for syntax validation)

### Environment Variables

- `GHIDRA_INSTALL_DIR` - Path to Ghidra installation
- `BATS_TEST_TIMEOUT` - Timeout for individual tests

### Test Binary

Tests require a test binary located at `../examples/ls`. This should be a valid binary file that can be analyzed by Ghidra.

## Running Tests

### Quick Start

```bash
# Run all tests
./run_tests.sh

# Check prerequisites only
./run_tests.sh --check

# Run specific test suites
./run_tests.sh basic advanced
```

### Test Suites

- `basic` - Essential functionality tests
- `advanced` - Feature-specific tests
- `validation` - Output quality tests
- `error` - Error handling and edge cases
- `recompilation` - Function recompilation tests
- `all` - All test suites (default)

### Command Line Options

```bash
./run_tests.sh [OPTIONS] [TEST_SUITES...]

OPTIONS:
  -h, --help              Show help message
  -c, --check             Only check prerequisites
  -v, --verbose           Enable verbose output
  --cleanup-only          Only run cleanup
  --no-cleanup            Skip cleanup after tests
  --parallel              Run test suites in parallel
```

### Examples

```bash
# Run all tests with verbose output
./run_tests.sh --verbose

# Run only basic and validation tests
./run_tests.sh basic validation

# Check environment and clean up
./run_tests.sh --check
./run_tests.sh --cleanup-only
```

## Test Environment

### Temporary Files

Tests create temporary files in:
- `$BATS_TEST_TMPDIR` - BATS-managed temporary directory for each test
- `/tmp/*ghidra*` - Ghidra temporary files

### Cleanup

The test framework automatically cleans up temporary files after each test and at the end of the test run.

## Writing New Tests

### Adding Test Cases

1. Choose the appropriate test file based on test category
2. Use the `load test_helper` directive to access helper functions
3. Follow BATS syntax: `@test "description" { ... }`
4. Use helper functions from `test_helper.bash`

### Example Test

```bash
@test "export creates valid C file" {
    local binary_path
    binary_path=$(check_test_binary "ls")
    
    run_export "$binary_path"
    [[ $status -eq 0 ]]
    
    check_exported_files
    validate_output_structure
}
```

### Helper Functions

Key helper functions available:

- `check_test_binary(name)` - Verify test binary exists
- `run_export(binary, args...)` - Execute export with timeout
- `check_exported_files()` - Verify output files exist
- `validate_output_structure()` - Check output file structure
- `check_c_compilation()` - Test C file compilation
- `count_functions()` - Count functions in output
- `function_exists(name)` - Check if function exists in output
- `test_function_recompilation(program_code, function_name, test_name)` - Test full compile → decompile → recompile workflow

### Adding Recompilation Tests

For recompilation tests, use the `test_function_recompilation` helper to test the full workflow:

```bash
@test "my function survives decompilation and recompilation" {    
    # Define a complete program with the function you want to test
    local program='#include <stdio.h>
void my_function() { 
    printf("Hello from my function\n"); 
}
int main() { 
    my_function(); 
    return 0; 
}'
    
    # Test the full workflow: compile → decompile → recompile
    test_function_recompilation "$program" "my_function" "my_test"
}
```

The workflow tests:
1. **Compilation**: Your source code is compiled to a binary
2. **Decompilation**: The binary is decompiled using the export script
3. **Function extraction**: The specified function is extracted from decompiled code
4. **Recompilation**: The extracted function is recompiled to an object file

## Continuous Integration

The test framework is designed to work in CI environments:

- Provides clear exit codes (0 = success, 1 = failure)
- Generates TAP (Test Anything Protocol) output
- Includes timeout handling for long-running tests
- Handles missing dependencies gracefully

## Troubleshooting

### Common Issues

1. **Missing GHIDRA_INSTALL_DIR**
   ```bash
   export GHIDRA_INSTALL_DIR=/path/to/ghidra
   ```

2. **Test binary not found**
   - Ensure `examples/ls` exists and is executable
   - Or provide alternative test binary

3. **Permission issues**
   - Ensure test scripts are executable
   - Check write permissions in test directory

### Debug Mode

Run individual test files directly for debugging:

```bash
# Run single test file
bats tests/basic_tests.bats

# Run with verbose output
bats --tap tests/basic_tests.bats

# Run specific test
bats --filter "export script exists" tests/basic_tests.bats
```

## Integration with Project

The test framework integrates with the main project through:

- Testing the `export.bash` script interface
- Validating `cpp_exporter_headless.py` functionality
- Using project examples and configuration
- Following project coding standards and practices
