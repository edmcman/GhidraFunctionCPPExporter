# Ghidra Function C++ Exporter - AI Agent Instructions

## Project Overview

This is a Ghidra headless script that exports decompiled C/C++ code from binaries with a focus on **function-level compilation** - the ability to export and recompile individual functions. It addresses limitations in Ghidra's built-in CppExporter by exporting only the minimal necessary types, function declarations, and globals for selected functions.

**Key differentiator**: Unlike Ghidra's default exporter, this produces compilable output for individual functions or subsets, not just entire programs.

## Architecture & Data Flow

### Core Pipeline (lines 622-1058 in cpp_exporter_headless.py)

```
1. Auto-analysis → 2. Decompile → 3. Collect Dependencies → 4. Write Output
```

1. **Auto-analysis** (lines 71-108): Always runs full Ghidra analysis before export. Optional Decompiler Parameter ID analysis improves variable naming
2. **Decompilation** (lines 547-603, `decompile_function()`): Uses Ghidra's `DecompInterface` to produce `CPPDecompileResult` objects containing:
   - Function signature
   - Function body (C code)
   - Referenced globals (via `HighSymbol` from P-code)
   - Referenced functions (by analyzing `PcodeOp.CALL` operations)
   - Markup types (extracted from `ClangTypeToken` objects)
3. **Dependency Collection** (lines 789-969): Recursively collects types, globals, and function declarations needed by decompiled functions
4. **Output Assembly** (lines 1000-1049): Generates C file and/or header file with section-based structure

### Key Data Structures

- **`CPPDecompileResult`** (lines 484-545): Container for all decompilation data - function signature, body, globals, called functions, markup types. Has `to_dict()` method for JSON serialization
- **Dependency tracking**: Uses Java `HashSet` and `ArrayList` for type/function/global tracking (jpype integration)
- **Section builders**: String lists (`h_types_sb`, `c_func_decls_sb`, `b_code_sb`, etc.) accumulate output sections

## Critical Workflows

### Running the Exporter

**Preferred method** (simple frontend):
```bash
export GHIDRA_INSTALL_DIR=/path/to/ghidra
./export.bash ./examples/ls address_set_str "0x1124c0"
```

**Direct Ghidra method**:
```bash
$GHIDRA_INSTALL_DIR/support/analyzeHeadless ~/ghidra_projects MyProject \
  -import ./binary -preScript cpp_exporter_headless.py \
  --address_set_str "0x1124c0" --create_c_file true
```

The `export.bash` script (lines 1-231) handles temporary project creation and cleanup automatically.

### Testing

**Test framework**: BATS (Bash Automated Testing System) with modern patterns
```bash
cd tests
./run_tests.sh              # All tests
./run_tests.sh basic        # Specific suite
```

**Test suites**: `basic_tests.bats`, `advanced_tests.bats`, `validation_tests.bats`, `error_tests.bats`, `performance_tests.bats`, `recompilation_tests.bats`, `separate_files_tests.bats`

**Key helper**: `run_export` function in `test_helper.bash` provides unified interface
- Uses BATS shorthand: `run_export -0 "$binary"` (expect success), `run_export ! "$binary"` (expect failure)
- Auto-manages temporary directories

## Project-Specific Patterns

### PyGhidra/JPype Integration

This script runs in Ghidra's Jython/PyGhidra environment with JPype for Java interop:

```python
from jpype import JImplements, JOverride  # For Java interface implementation
from java.io import File, PrintWriter, StringWriter
from java.util import ArrayList, HashSet
from ghidra.app.decompiler import DecompInterface, ClangTypeToken
```

**Critical**: Use Java collections (`HashSet`, `ArrayList`), not Python sets/lists, when interfacing with Ghidra APIs.

### Type Dependency Resolution (lines 127-158)

Recursive type collection pattern for pointers, arrays, typedefs, composites, and function definitions:

```python
def collect_dependent_types(dt, program_dtm, collected_set):
    if dt is None or dt in collected_set:
        return
    collected_set.add(dt)
    
    if isinstance(dt, Pointer):
        collect_dependent_types(dt.getDataType(), program_dtm, collected_set)
    elif isinstance(dt, Composite):
        for comp in dt.getComponents():
            collect_dependent_types(comp.getDataType(), program_dtm, collected_set)
```

**Key insight**: Types are added to set *before* recursion to handle circular type definitions.

### Markup Type Extraction (lines 208-246)

Types are extracted from decompiled C code markup using `ClangTypeToken`:

```python
token_group = decompile_results.getCCodeMarkup()
flattened_tokens = ArrayList()
token_group.flatten(flattened_tokens)

for token in flattened_tokens:
    if isinstance(token, ClangTypeToken):
        markup_types.add(token.getDataType())
```

This captures types from casts, variable declarations, and all type references in the decompiled code.

### Argument Parsing (lines 1065-1204)

Uses Python's `argparse` for structured CLI parsing. Arguments can be passed in two formats:
- Direct argparse: `--output_dir /tmp --create_c_file true`
- Ghidra key-value: `output_dir /tmp create_c_file true`

Special boolean parser accepts: `true/false`, `1/0`, `yes/no`, `on/off`, `enable/disable`

### Section-Based Output Structure

Output files organized into standardized sections with headers (see `create_section_header()` lines 294-311):

1. **DATA TYPES** - Type definitions extracted from program
2. **EQUATES** - `#define` statements from equate table
3. **FUNCTION DECLARATIONS** - Prototypes for referenced functions
4. **GLOBAL VARIABLES** - `extern` declarations for globals
5. **FUNCTION IMPLEMENTATIONS** - Decompiled function bodies

## Code Style Conventions

- **Functional preference**: Favor functional programming, conciseness, and simplicity (from workspace instructions)
- **Minimal code changes**: When adding features, refactor existing code into helpers and reuse
- **Logging**: Use `log_message(level, message)` helper with levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
- **Error handling**: Decompilation failures return `None` or minimal `CPPDecompileResult` with error comments
- **String building**: Use string lists and `"".join()` for large outputs (e.g., `h_types_sb = []`)

## Integration Points

### External Dependencies

- **Ghidra**: Must be installed with `GHIDRA_INSTALL_DIR` environment variable set
- **GCC**: Used in validation tests for syntax checking (not runtime dependency)
- **BATS**: For running test suite

### Output Formats

Currently supports:
- C source files (`.c`)
- Header files (`.h`)

**Planned**: JSON output format capturing header text and function bodies with minimal code changes

### Filtering Mechanisms (lines 677-779)

Three filtering modes:
1. **Function tags**: `--function_tag_filters "TAG1,TAG2"` with include/exclude toggle
2. **Address ranges**: `--address_set_str "0x1000-0x2000,0x3000"`
3. **Function names**: `--include_functions_only "foo,bar,baz"`

## Development Notes

- **No Jupyter notebooks**: Plain Python file, not notebook-based
- **Headless operation**: Designed for CI/CD and automated workflows
- **Binary test data**: `examples/ls` is the standard test binary
- **Temp projects**: `export.bash` creates/destroys temporary Ghidra projects in `/tmp`
