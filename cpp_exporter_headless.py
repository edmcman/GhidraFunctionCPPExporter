#@runtime PyGhidra
# =============================================================================
# Ghidra Headless C/C++ Code Exporter
# =============================================================================
#
# This script exports decompiled C/C++ code from a Ghidra program, similar to
# the built-in CppExporter.java plugin but designed to run in headless mode.
# It performs a full auto-analysis before exporting, making it suitable to run
# as a pre-analysis script.
#
# Features:
# - Export to C source and header files
# - Filter functions by tags, address ranges, or function names
# - Include function declarations for referenced functions
# - Export only necessary data types and globals
# - Configurable comment style (C or C++)
#
# Usage with analyzeHeadless:
# analyzeHeadless <project_location> <project_name> -process <program_name> \
#   -preScript cpp_exporter_headless.py <option_name> <option_value> ...
#
# Available options:
#   output_dir              Output directory path (default: ".")
#   base_name               Base name for output files (default: program name)
#   create_c_file           Create C implementation file (true/false)
#   create_header_file      Create header file (true/false)
#   use_cpp_style_comments  Use C++ style comments (true/false)
#   emit_type_definitions   Include type definitions (true/false)
#   emit_referenced_globals Include global variables (true/false)
#   function_tag_filters    Function tags to filter by ("TAG1,TAG2")
#   function_tag_exclude    Exclude (vs include) matching tags (true/false)
#   address_set_str         Address ranges to process ("0x1000-0x2000,0x3000")
#   emit_function_declarations Include function prototypes (true/false)
#   include_functions_only  Include only named functions ("foo,bar,baz")
#   run_decompiler_parameter_id Run Parameter ID analysis for better variable names (true/false)
#
# Note: Auto-analysis is always run before exporting. Decompiler Parameter ID analysis 
# can significantly improve variable naming and parameter identification but may 
# increase processing time.

from ghidra.app.plugin.core.analysis import AutoAnalysisManager # type: ignore
from ghidra.app.decompiler import DecompInterface, DecompileOptions # type: ignore
from ghidra.app.decompiler import ClangTypeToken # type: ignore
from ghidra.program.model.address import AddressSet # type: ignore
from ghidra.program.model.data import ( # type: ignore
    DataTypeWriter,
    Composite,        # Added
    FunctionDefinition, # Added
    Pointer,          # Added
    Array,            # Added
    TypedefDataType   # Changed from Typedef
)
from ghidra.program.model.symbol import SymbolType # type: ignore # Added SourceType
from ghidra.program.model.pcode import PcodeOp  # type: ignore # Added HighSymbol here
from ghidra.util.task import ConsoleTaskMonitor # type: ignore
from ghidra.app.util.headless.HeadlessScript import HeadlessContinuationOption

import os
import sys
import traceback
import argparse
from java.io import File, PrintWriter, StringWriter # type: ignore
from java.util import ArrayList, HashSet, Collections # type: ignore
# PyGhidra/JPype compatibility: Use @JImplements decorator instead of direct inheritance
# from java.lang.Comparable. Import JImplements and JOverride from jpype.
from jpype import JImplements, JOverride  # type: ignore
from java.lang import Comparable  # type: ignore

def run_analyzer(program, task_monitor, enable_param_id=False):
    """
    Run auto-analysis on the program with optional Decompiler Parameter ID analysis.
    
    This function triggers a complete reanalysis of the program, including 
    all enabled analyzers. It can optionally enable the Decompiler Parameter ID 
    analyzer before running to improve variable names and types in decompilation.
    
    Args:
        program: The Ghidra program object
        task_monitor: TaskMonitor for tracking progress
        enable_param_id: Whether to enable Decompiler Parameter ID analyzer
    """
    if enable_param_id:
        log_message("INFO", "Running full auto-analysis with Decompiler Parameter ID enabled...")
        # Get the analysis options
        options = program.getOptions("Analyzers")
        
        # Enable Decompiler Parameter ID analyzer
        options.setBoolean("Decompiler Parameter ID", True)
    else:
        log_message("INFO", "Running full auto-analysis...")
        
    auto_analysis_manager = AutoAnalysisManager.getAnalysisManager(program)
    auto_analysis_manager.setDebug(True)
    
    # Run the analysis
    auto_analysis_manager.reAnalyzeAll(None)
    auto_analysis_manager.startAnalysis(task_monitor)

    if enable_param_id:
        log_message("INFO", "Auto-analysis with Decompiler Parameter ID completed")
    else:
        log_message("INFO", "Auto-analysis completed")


param_output_dir = "."
param_base_name = (
    currentProgram.getName() if "currentProgram" in globals() else "exported_program" # type: ignore
)
param_create_c_file = True
param_create_header_file = False
param_use_cpp_style_comments = True
param_emit_type_definitions = True
param_emit_referenced_globals = True
param_function_tag_filters = ""
param_function_tag_exclude = True
param_address_set_str = None
param_emit_function_declarations = True
param_include_functions_only = None  # Added new parameter
param_run_decompiler_parameter_id = True  # Run Decompiler Parameter ID analysis by default

EOL = os.linesep

# --- Helper Functions ---


def collect_dependent_types(dt, program_dtm, collected_set):
    """
    Recursively collects all dependent data types for a given type.
    """
    if dt is None or dt in collected_set:
        return

    # Add the type itself.
    # We add it first to handle recursive type definitions gracefully.
    collected_set.add(dt)

    # For pointers, arrays, and typedefs, get the base/referenced type and recurse.
    if isinstance(dt, Pointer):
        collect_dependent_types(dt.getDataType(), program_dtm, collected_set)
    elif isinstance(dt, Array):
        collect_dependent_types(dt.getDataType(), program_dtm, collected_set)
    elif isinstance(dt, TypedefDataType):  # Changed from Typedef
        collect_dependent_types(dt.getBaseDataType(), program_dtm, collected_set)
    # For composites (structs, unions), recurse for each component.
    elif isinstance(dt, Composite):
        for comp in dt.getComponents():
            collect_dependent_types(comp.getDataType(), program_dtm, collected_set)
    # For function definitions (used in function pointers), recurse for return and arg types.
    elif isinstance(dt, FunctionDefinition):
        collect_dependent_types(dt.getReturnType(), program_dtm, collected_set)
        for arg in dt.getArguments():
            collect_dependent_types(arg.getDataType(), program_dtm, collected_set)


def extract_markup_types_from_decompile_results(decompile_results, program_dtm):
    """
    Extract data types from the C code markup of a decompiled function.
    
    This function iterates over the C code markup and looks for ClangTypeToken
    objects that represent type information used throughout the decompiled code,
    including casts, variable declarations, and other type references.
    
    Args:
        decompile_results: The DecompileResults object
        program_dtm: The program's DataTypeManager
        
    Returns:
        HashSet: Set of DataType objects found in the markup
    """
    markup_types = HashSet()
    
    log_message("DEBUG", "Extracting types from decompiled function markup")

    try:
        # Get the ClangTokenGroup from the decompile results
        token_group = decompile_results.getCCodeMarkup()
        
        if token_group is None:
            return markup_types
            
        # Flatten all tokens from the token group
        flattened_tokens = ArrayList()
        token_group.flatten(flattened_tokens)
        
        # Iterate through all flattened tokens
        for token in flattened_tokens:
            # Look for ClangTypeToken objects which represent type information
            if isinstance(token, ClangTypeToken):
                data_type = token.getDataType()
                if data_type is not None:
                    markup_types.add(data_type)
                    log_message("DEBUG", "Found markup type: {}".format(data_type.getDisplayName()))
                    
    except Exception as e:
        log_message("WARNING", "Error extracting markup types: {}".format(str(e)))
        
    return markup_types


def get_fake_c_type_definitions(data_organization):
    writer = StringWriter()

    def get_built_in_declaration(type_name, ctype_name_or_len, signed=False, org=None):
        """Helper function to generate C-type definitions using typedef"""
        if isinstance(ctype_name_or_len, str):
            return "typedef {} {};{}".format(ctype_name_or_len, type_name, EOL)
        elif org is not None:
            base_type = org.getIntegerCTypeApproximation(ctype_name_or_len, signed)
            return "typedef {} {};{}".format(base_type, type_name, EOL)
        else:
            # Fallback when data organization is not available
            return "typedef int {};{}".format(type_name, EOL)

    for n in range(9, 17):
        writer.write(
            get_built_in_declaration("unkbyte{}".format(n), n, False, data_organization)
        )
    writer.write(EOL)
    for n in range(9, 17):
        writer.write(
            get_built_in_declaration("unkuint{}".format(n), n, False, data_organization)
        )
    writer.write(EOL)
    for n in range(9, 17):
        writer.write(
            get_built_in_declaration("unkint{}".format(n), n, True, data_organization)
        )
    writer.write(EOL)
    writer.write(get_built_in_declaration("unkfloat1", "float"))
    writer.write(get_built_in_declaration("unkfloat2", "float"))
    writer.write(get_built_in_declaration("unkfloat3", "float"))
    writer.write(get_built_in_declaration("unkfloat5", "double"))
    writer.write(get_built_in_declaration("unkfloat6", "double"))
    writer.write(get_built_in_declaration("unkfloat7", "double"))
    writer.write(get_built_in_declaration("unkfloat9", "long double"))
    for n in range(11, 17):
        writer.write(get_built_in_declaration("unkfloat{}".format(n), "long double"))
    writer.write(EOL)
    writer.write(get_built_in_declaration("BADSPACEBASE", "void"))
    writer.write(get_built_in_declaration("code", "void"))
    writer.write(EOL)
    
    # Add typedef for bool when not in C++ mode and NO_BOOL is not defined
    writer.write("// C99 lacks bool, define it as byte for C-only output\n")
    writer.write("#if !defined(__cplusplus) && !defined(NO_BOOL)\n")
    writer.write("typedef unsigned char bool;\n")
    writer.write("#endif\n")
    writer.write(EOL)
    
    writer.write(EOL)
    
    return writer.toString()


def create_section_header(title, description, use_cpp_comments=True):
    """
    Generate a standardized section header comment block.
    
    Args:
        title (str): The title of the section
        description (str): Description text for the section
        use_cpp_comments (bool): Whether to use C++ style comments
        
    Returns:
        str: Formatted section header
    """
    comment_style = "//" if use_cpp_comments else "/*"
    end_comment = "" if use_cpp_comments else " */"
    
    return """
{0}=============================================================================={1}
{0} {2:<74}{1}
{0} {3:<74}{1}
{0}=============================================================================={1}
""".format(comment_style, end_comment, title, description)


def write_equates(program, writer, monitor):
    """
    Write equate definitions (#define) to the output file.
    
    Args:
        program: The Ghidra program object
        writer: PrintWriter for the output file
        monitor: TaskMonitor to report progress and check for cancellation
    """
    equate_table = program.getEquateTable()
    equates_present = False
    
    # Check if we have any equates first before writing the header
    has_equates = False
    for _ in equate_table.getEquates():
        has_equates = True
        break
        
    if has_equates and writer is not None:
        # Add equates section header comment
        use_cpp_comments = True  # Default to C++ comments
        try:
            # Try to determine comment style from DecompileOptions if available
            if hasattr(writer, 'getOptions') and hasattr(writer.getOptions(), 'getCommentStyle'):
                use_cpp_comments = writer.getOptions().getCommentStyle() == DecompileOptions.CommentStyleEnum.CPPStyle
        except:
            pass  # Ignore errors and stick with default
            
        equates_header = create_section_header(
            "EQUATES / DEFINES",
            "Constants and named values extracted from the binary",
            use_cpp_comments
        )
        writer.println(equates_header)
    
    for equate in equate_table.getEquates():
        monitor.checkCancelled()
        equates_present = True
        writer.println(
            "#define {} {}{}".format(
                equate.getDisplayName(), equate.getDisplayValue(), EOL
            )
        )
    if equates_present and writer is not None:
        writer.println()


def write_program_data_types(
    program, header_file_obj, header_writer, c_file_writer, monitor, use_cpp_comments,
    specific_types_to_write=None  # Added new optional parameter
):
    dtm = program.getDataTypeManager()
    data_org = dtm.getDataOrganization()
    fake_types_def = get_fake_c_type_definitions(data_org)

    target_writer = header_writer if header_writer else c_file_writer
    if not target_writer:
        return
        
    # Add types section header
    types_header = create_section_header(
        "DATA TYPES",
        "These types were decompiled from the binary and may not match original source",
        use_cpp_comments
    )

    if header_writer:
        header_writer.println(types_header)
        dt_writer = DataTypeWriter(dtm, header_writer, use_cpp_comments)
        header_writer.write(fake_types_def)
        if specific_types_to_write is not None:
            dt_writer.write(specific_types_to_write, monitor)  # Use specific list
        else:
            dt_writer.write(dtm, monitor)  # Original behavior
        header_writer.println()
        header_writer.println()
        if c_file_writer and header_file_obj:
            c_file_writer.println('#include "{}"'.format(header_file_obj.getName()))
    elif c_file_writer:  # Only C file
        c_file_writer.println(types_header)
        dt_writer = DataTypeWriter(dtm, c_file_writer, use_cpp_comments)
        c_file_writer.write(fake_types_def)
        if specific_types_to_write is not None:
            dt_writer.write(specific_types_to_write, monitor)  # Use specific list
        else:
            dt_writer.write(dtm, monitor)  # Original behavior

    if c_file_writer:
        c_file_writer.println()
        c_file_writer.println()


def get_function_signature(func_obj, decompiler, decompiler_opts, mon, is_external=False):
    """
    Generate a signature string for a function.
    
    Args:
        func_obj: Ghidra Function object
        decompiler: DecompInterface instance
        decompiler_opts: DecompileOptions instance
        mon: TaskMonitor for progress tracking
        is_external: Boolean flag indicating if the function is external
        
    Returns:
        str: Generated function signature string or None if failed
    """
    func_name = func_obj.getName()
    
    if is_external:
        proto_str = func_obj.getPrototypeString(True, False)
        if proto_str and proto_str.strip():
            sig = proto_str.strip()
            if not sig.endswith(";"):
                sig += ";"
            return sig
    
    # Use decompiler for non-external functions or if external handling failed
    try:
        decompile_results = decompiler.decompileFunction(func_obj, decompiler_opts.getDefaultTimeout(), mon)
        if decompile_results and decompile_results.getDecompiledFunction():
            sig_str = decompile_results.getDecompiledFunction().getSignature()
            if sig_str and sig_str.strip():
                sig = sig_str.strip()
                if not sig.endswith(";"):
                    sig += ";"
                return sig
    except Exception as e:
        print("WARNING: Failed to decompile {}: {}".format(func_name, str(e)))
        
    return None


def parse_function_tags(program, tag_options_str):
    """
    Parse function tags from a comma-separated string.
    
    Args:
        program: Ghidra Program object
        tag_options_str: Comma-separated list of tag names
        
    Returns:
        HashSet: Set of function tags
    """
    tag_set = HashSet()
    if not tag_options_str or not tag_options_str.strip():
        return tag_set
        
    fm = program.getFunctionManager()
    tag_manager = fm.getFunctionTagManager()
    
    # Process each tag name
    found_tags = []
    missing_tags = []
    for tag_name in tag_options_str.split(","):
        tag_name = tag_name.strip()
        if not tag_name:
            continue
            
        tag = tag_manager.getFunctionTag(tag_name)
        if tag:
            tag_set.add(tag)
            found_tags.append(tag_name)
        else:
            missing_tags.append(tag_name)
    
    # Log results
    if found_tags:
        log_message("INFO", "Found function tags: {}".format(', '.join(found_tags)))
    if missing_tags:
        log_message("WARNING", "Could not find function tags: {}".format(', '.join(missing_tags)))
        
    return tag_set


def exclude_function_by_tags(func, function_tag_set, exclude_matching):
    """
    Determine if a function should be excluded based on its tags.
    
    Args:
        func: Function object to check
        function_tag_set: Set of tags to match against
        exclude_matching: If True, exclude functions with matching tags;
                         if False, exclude functions without matching tags
                         
    Returns:
        bool: True if function should be excluded, False otherwise
    """
    # If no tags specified, include all functions
    if function_tag_set.isEmpty():
        return False
        
    # Check if function has any matching tags
    tags_on_function = func.getTags()
    has_matching_tag = any(
        tags_on_function.contains(tag_in_filter_set)
        for tag_in_filter_set in function_tag_set
    )
    
    # Determine whether to exclude based on the exclusion mode
    return exclude_matching == has_matching_tag

@JImplements("java.lang.Comparable")
class CPPDecompileResult:
    """
    Class to represent the result of decompiling a function.
    
    This class implements the Java Comparable interface using JPype's @JImplements
    decorator to allow sorting of results by address.

    Attributes:
        function_obj (Function): Ghidra Function object
        header_code (str): Function signature/declaration code
        body_code (str): Function implementation code
        referenced_ghidra_globals (list): List of HighSymbol objects for globals referenced by this function
        referenced_ghidra_functions (list): List of Function objects called by this function
        markup_types (set): Set of DataType objects extracted from decompiled markup
    """
    def __init__(self, function_obj, header_code, body_code, referenced_ghidra_globals=None, referenced_ghidra_functions=None, markup_types=None):
        """
        Initialize a decompile result.
        
        Args:
            function_obj: The Ghidra Function object
            header_code: Function signature/prototype string
            body_code: Function implementation code
            referenced_ghidra_globals: List of HighSymbol objects (defaults to empty list)
            referenced_ghidra_functions: List of Function objects (defaults to empty list)
            markup_types: Set of DataType objects from markup (defaults to empty set)
        """
        self.function_obj = function_obj
        self.header_code = header_code
        self.body_code = body_code
        self.referenced_ghidra_globals = referenced_ghidra_globals or []
        self.referenced_ghidra_functions = referenced_ghidra_functions or []
        self.markup_types = markup_types or HashSet()

    def __lt__(self, other):
        """Python less-than comparison method"""
        if not isinstance(other, CPPDecompileResult):
            return NotImplemented
        return self.function_obj.getEntryPoint().compareTo(other.function_obj.getEntryPoint()) < 0

    # PyGhidra/JPype compatibility: Use @JOverride decorator to mark this method as
    # implementing the Java Comparable.compareTo() interface method.
    @JOverride
    def compareTo(self, other):
        """Java Comparable interface implementation"""
        if not isinstance(other, CPPDecompileResult):
            return 0
        return self.function_obj.getEntryPoint().compareTo(other.function_obj.getEntryPoint())


def decompile_function_ghidra(func, decompiler_iface, decompiler_options, monitor):
    """
    Decompile a function using Ghidra's decompiler.
    
    Args:
        func: Ghidra Function object to decompile
        decompiler_iface: DecompInterface instance
        decompiler_options: DecompileOptions instance
        monitor: TaskMonitor for progress tracking
        
    Returns:
        CPPDecompileResult object or None if decompilation failed
    """
    try:
        func_name = func.getName()
        monitor.setMessage("Decompiling {}".format(func_name))
        
        results = decompiler_iface.decompileFunction(
            func, decompiler_options.getDefaultTimeout(), monitor
        )
        error_message = results.getErrorMessage()

        if error_message:
            log_message("ERROR", "Error decompiling {}: {}".format(func_name, error_message))
            if decompiler_options.isWARNCommentIncluded():
                body = "/*{}Unable to decompile '{}'{}Cause: {}{}*/{}".format(
                    EOL, func_name, EOL, error_message, EOL, EOL
                )
                return CPPDecompileResult(func, None, body, [], [], HashSet())
            return None
    except Exception as e:
        log_message("ERROR", "Exception when decompiling {}: {}".format(func.getName(), str(e)))
        return None

    try:
        decompiled_func = results.getDecompiledFunction()
        if not decompiled_func:
            # If we get here, we have a result but no decompiled function
            return CPPDecompileResult(
                func,
                func.getPrototypeString(False, False) + ";",
                "/* Could not decompile {} */{}".format(func.getName(), EOL),
                [],
                [],
                HashSet()
            )

        # Process the successful decompilation
        collected_globals = []
        collected_called_functions = []
        high_func = results.getHighFunction()
        
        if high_func:
            # Collect referenced global symbols
            try:
                global_symbol_map = high_func.getGlobalSymbolMap()
                if global_symbol_map:
                    for hsym in global_symbol_map.getSymbols():
                        collected_globals.append(hsym)
            except Exception as e:
                log_message("WARNING", "Error collecting globals for {}: {}".format(func.getName(), str(e)))
                
            # Collect referenced functions
            try:
                pcode_ops = high_func.getPcodeOps()
                function_manager = func.getProgram().getFunctionManager()
                while pcode_ops.hasNext():
                    op = pcode_ops.next()
                    if op.getOpcode() == PcodeOp.CALL:
                        call_dest_addr = op.getInput(0).getAddress()
                        if call_dest_addr:
                            called_func_obj = function_manager.getFunctionAt(call_dest_addr)
                            if called_func_obj and called_func_obj not in collected_called_functions:
                                collected_called_functions.append(called_func_obj)
            except Exception as e:
                log_message("WARNING", "Error collecting called functions for {}: {}".format(func.getName(), str(e)))

        # Extract types from the decompiled function markup
        markup_types = extract_markup_types_from_decompile_results(results, func.getProgram().getDataTypeManager())

        return CPPDecompileResult(
            func,
            decompiled_func.getSignature(),
            decompiled_func.getC(),
            collected_globals,
            collected_called_functions,
            markup_types
        )
    except Exception as e:
        log_message("ERROR", "Error processing decompiled function {}: {}".format(func.getName(), str(e)))
        # Return a minimal result with just the prototype
        return CPPDecompileResult(
            func,
            func.getPrototypeString(False, False) + ";",
            "/* Error processing decompilation of {}: {} */{}".format(func.getName(), str(e), EOL),
            [],
            [],
            HashSet()
        )


def log_message(level, message):
    """
    Simple logging function to standardize log output.
    
    Args:
        level: String indicating log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        message: Message to log
    """
    print("{}: {}".format(level, message))


def run_export_main(
    current_program,
    out_dir,
    base_fname,
    create_c,
    create_h,
    use_cpp_cmt,
    emit_dt,
    emit_g,
    tag_filters,
    exclude_tags,
    addr_set_filter_str,
    emit_func_decls,
    mon,
    include_functions_only=None
):
    # Always run auto-analysis, optionally with Decompiler Parameter ID
    run_analyzer(current_program, mon, param_run_decompiler_parameter_id)
    
    # Log appropriate message
    if param_run_decompiler_parameter_id:
        log_message("INFO", "Auto-analysis with Decompiler Parameter ID completed")
    else:
        log_message("INFO", "Auto-analysis completed (Decompiler Parameter ID disabled)")

    # Initialize decompiler with appropriate options
    try:
        log_message("INFO", "Initializing decompiler...")
        decompiler_opts = DecompileOptions()
        
        # Set comment style based on user preference
        comment_style = (
            DecompileOptions.CommentStyleEnum.CPPStyle
            if use_cpp_cmt
            else DecompileOptions.CommentStyleEnum.CStyle
        )
        decompiler_opts.setCommentStyle(comment_style)
        comment_style_text = "C++" if use_cpp_cmt else "C"
        log_message("INFO", "Using {} style comments".format(comment_style_text))
        
        # Create and configure decompiler interface
        decompiler = DecompInterface()
        decompiler.setOptions(decompiler_opts)
        
        # Open the program for decompilation
        if not decompiler.openProgram(current_program):
            log_message("ERROR", "Failed to open program with decompiler")
            return False
            
        # Enable syntax tree for better analysis
        decompiler.toggleSyntaxTree(True)
        log_message("INFO", "Decompiler initialized successfully")
    except Exception as e:
        log_message("ERROR", "Failed to initialize decompiler: {}".format(str(e)))
        return False

    out_dir_fobj = File(out_dir)
    out_dir_fobj.mkdirs()
    c_fobj, h_fobj, c_pw, h_pw = None, None, None, None

    if create_h:
        h_fobj = File(out_dir_fobj, base_fname + ".h")
        h_pw = PrintWriter(h_fobj)
        print("Creating header file: {}".format(h_fobj.getAbsolutePath()))
    if create_c:
        c_fobj = File(out_dir_fobj, base_fname + ".c")
        c_pw = PrintWriter(c_fobj)
        print("Creating C file: {}".format(c_fobj.getAbsolutePath()))

    if not c_pw and not h_pw:
        print("No output files selected.")
        decompiler.dispose()
        return False

    try:
        types_for_writer = None
        program_dtm = current_program.getDataTypeManager()

        func_mgr = current_program.getFunctionManager()
        parsed_tags = parse_function_tags(current_program, tag_filters)

        # Get address set to process (full memory or filtered by address)
        addr_set = current_program.getMemory()
        if addr_set_filter_str:
            log_message("INFO", "Applying address filter: {}".format(addr_set_filter_str))
            try:
                temp_addr_set = AddressSet()
                addr_factory = current_program.getAddressFactory()
                
                for part in addr_set_filter_str.split(","):
                    part = part.strip()
                    if not part:
                        continue
                        
                    if "-" in part:
                        # Handle address range (start-end)
                        start_str, end_str = part.split("-", 1)
                        start_addr = addr_factory.getAddress(start_str.strip())
                        end_addr = addr_factory.getAddress(end_str.strip())
                        
                        if start_addr is None or end_addr is None:
                            log_message("WARNING", "Invalid address range: {}".format(part))
                            continue
                            
                        temp_addr_set.addRange(start_addr, end_addr)
                        log_message("DEBUG", "Added address range: {} to {}".format(start_addr, end_addr))
                    else:
                        # Handle single address
                        addr = addr_factory.getAddress(part)
                        if addr is None:
                            log_message("WARNING", "Invalid address: {}".format(part))
                            continue
                            
                        temp_addr_set.add(addr)
                        log_message("DEBUG", "Added single address: {}".format(addr))
                
                if temp_addr_set.isEmpty():
                    log_message("WARNING", "Address set is empty after parsing. Using full memory range.")
                else:
                    addr_set = temp_addr_set
                    log_message("INFO", "Using filtered address set with {} ranges".format(temp_addr_set.getNumAddressRanges()))
            except Exception as e_addr:
                log_message("ERROR", "Error parsing address set '{}': {}".format(addr_set_filter_str, e_addr))
                log_message("INFO", "Using full memory range instead")

        funcs_to_process = [f for f in func_mgr.getFunctions(addr_set, True)]
        mon.initialize(len(funcs_to_process))

        # Process include_functions_only filter if specified
        include_functions_set = None
        if include_functions_only:
            include_functions_set = set()
            for fname in include_functions_only.split(","):
                fname = fname.strip()
                if fname:
                    include_functions_set.add(fname)
                    
            if include_functions_set:
                log_message("INFO", "Including only specific functions: {}".format(', '.join(include_functions_set)))
            else:
                log_message("WARNING", "include_functions_only parameter was empty")
                include_functions_set = None

        results_list = []
        processed_g_set = HashSet()
        mon.setMessage("Decompiling functions...")

        # Process each function, applying filters and decompiling
        for func_item in funcs_to_process:
            mon.checkCancelled()
            func_name = func_item.getName()
            
            # Apply tag filter
            if exclude_function_by_tags(func_item, parsed_tags, exclude_tags):
                mon.incrementProgress(1)
                continue
            
            # Apply function name filter
            if include_functions_set and func_name not in include_functions_set:
                mon.incrementProgress(1)
                continue

            # Decompile the function
            res = decompile_function_ghidra(func_item, decompiler, decompiler_opts, mon)
            if res:
                results_list.append(res)
            mon.incrementProgress(1)

        results_list.sort()
        mon.setMessage("Writing decompiled code...")

        # Collect types if type emission is enabled AND any function filtering is active
        if emit_dt and (param_address_set_str or param_include_functions_only):
            mon.setMessage("Collecting relevant data types...")
            directly_used_types = HashSet()
            
            all_emitted_functions = HashSet()
            for res_item in results_list:
                all_emitted_functions.add(res_item.function_obj)
                for called_func in res_item.referenced_ghidra_functions:
                    all_emitted_functions.add(called_func)
            
            for func_obj in all_emitted_functions:
                if func_obj.getReturnType() is not None:
                    directly_used_types.add(func_obj.getReturnType())
                for param in func_obj.getParameters():
                    if param.getDataType() is not None:
                        directly_used_types.add(param.getDataType())
            
            # Add types extracted from decompiled function markup
            for res_item in results_list:
                if res_item.markup_types:
                    for markup_type in res_item.markup_types:
                        directly_used_types.add(markup_type)
                    log_message("INFO", "Added {} markup types from function {}".format(
                        res_item.markup_types.size(), res_item.function_obj.getName()
                    ))

            if emit_g:
                for res_item in results_list:
                    for hsym in res_item.referenced_ghidra_globals:
                        if hsym.getDataType() is not None:
                            directly_used_types.add(hsym.getDataType())
            
            all_required_types_for_export = HashSet()
            for dt in directly_used_types:
                collect_dependent_types(dt, program_dtm, all_required_types_for_export)
            
            types_for_writer = ArrayList(all_required_types_for_export)
            log_message("DEBUG", "Number of types selected for filtered export: {}".format(types_for_writer.size()))
            
            # You could enable more detailed type analysis by uncommenting:
            # all_program_types_iterator = program_dtm.getAllDataTypes()
            # all_program_types_list = ArrayList()
            # while all_program_types_iterator.hasNext():
            #    all_program_types_list.add(all_program_types_iterator.next())
            # log_message("DEBUG", "Total number of types in program: {}".format(all_program_types_list.size()))

        if emit_dt:
            mon.setMessage("Writing data types and equates...")
            write_equates(current_program, h_pw if h_pw else c_pw, mon)
            write_program_data_types(
                current_program, h_fobj, h_pw, c_pw, mon, use_cpp_cmt, types_for_writer
            )
            mon.checkCancelled()
        
        all_declarations_to_emit = HashSet()
        g_decls_sb, b_code_sb = [], []

        for res_item in results_list:
            mon.checkCancelled()
            if emit_g and res_item.referenced_ghidra_globals:
                for hsym in res_item.referenced_ghidra_globals:
                    dt = hsym.getDataType()
                    if dt is None: continue
                    
                    name = hsym.getName()
                    is_function_pointer = hsym.getSymbol() is not None and hsym.getSymbol().getSymbolType() == SymbolType.FUNCTION
                    
                    if is_function_pointer:
                        # Generate a function prototype declaration instead of a global variable
                        print("INFO: Processing {} as a function pointer".format(name))
                        function_mgr = current_program.getFunctionManager()
                        function_address = hsym.getSymbol().getAddress()

                        if function_address is None:
                            print("WARNING: Function pointer address is None for {}".format(name))
                            continue
                            
                        func_obj = function_mgr.getFunctionAt(function_address)
                        if func_obj is None:
                            print("WARNING: Could not find function at address {} for {}".format(function_address, name))
                            continue
                        
                        # Get the function signature
                        func_prototype = get_function_signature(func_obj, decompiler, decompiler_opts, mon)
                        if func_prototype:
                            all_declarations_to_emit.add(func_prototype)
                            print("INFO: Added function declaration for {}".format(name))
                            continue  # Skip adding as a global variable
                    
                    # Regular global variable processing
                    dt_name = dt.getDisplayName()
                    
                    # Handle array types correctly - move array dimensions after variable name
                    if "[" in dt_name and "]" in dt_name:
                        # Extract base type and array dimensions
                        bracket_start = dt_name.find("[")
                        base_type = dt_name[:bracket_start]
                        array_dims = dt_name[bracket_start:]
                        space = "" if base_type.endswith("*") else " "
                        g_var_decl = "{}{}{}{};".format(base_type, space, name, array_dims)
                    else:
                        space = "" if dt_name.endswith("*") or dt_name.endswith("]") or isinstance(dt, FunctionDefinition) else " "
                        g_var_decl = "{}{}{};".format(dt_name, space, name)
                    
                    if processed_g_set.add(g_var_decl):
                        g_decls_sb.extend([g_var_decl, EOL])
            
            if res_item.body_code:
                b_code_sb.extend([res_item.body_code, EOL])

            if emit_func_decls:
                if res_item.header_code: # Signature of the primary function
                    all_declarations_to_emit.add(res_item.header_code)
                
                if res_item.referenced_ghidra_functions: # List of Function objects
                    for called_func_obj in res_item.referenced_ghidra_functions:
                        # Get function name for error reporting
                        func_name = "UNKNOWN_FUNCTION"
                        try:
                            func_name = called_func_obj.getName()
                        except:
                            pass
                            
                        # Handle thunked functions
                        actual_func_for_sig = called_func_obj
                        try:
                            if called_func_obj.isThunk():
                                thunked_target = called_func_obj.getThunkedFunction(True)
                                if thunked_target:
                                    effective_name = thunked_target.getName()
                                    print("INFO: Function {} is a thunk. Using thunked function {} for signature.".format(func_name, effective_name))
                                    actual_func_for_sig = thunked_target
                        except Exception as e:
                            print("WARNING: Error processing thunk for {}: {}".format(func_name, e))
                        
                        # Get effective name for logging
                        effective_name = func_name
                        try:
                            effective_name = actual_func_for_sig.getName()
                        except:
                            pass
                        
                        # Generate signature based on whether it's an external function
                        is_external = False
                        try:
                            is_external = actual_func_for_sig.isExternal()
                        except:
                            pass
                            
                        if is_external:
                            print("INFO: Function {} is external. Using direct prototype string.".format(effective_name))
                            
                        # Get the function signature
                        generated_prototype = get_function_signature(
                            actual_func_for_sig, 
                            decompiler, 
                            decompiler_opts, 
                            mon,
                            is_external
                        )
                        
                        # Add the generated signature or an error comment
                        if generated_prototype:
                            all_declarations_to_emit.add(generated_prototype)
                            print("INFO: Used signature for {} (effective: {}): {}".format(func_name, effective_name, generated_prototype))
                        else:
                            error_comment = "/* WARNING: Could not decompile function {} */".format(effective_name)
                            all_declarations_to_emit.add(error_comment)
                            print("WARNING: Failed to generate a prototype for {}. Adding error comment.".format(func_name))
        
        h_func_decls_sb, c_func_decls_sb = [], []
        h_globals_sb, c_globals_sb = [], []
        
        if emit_func_decls:
            # Create function declarations header comment
            func_decl_header = create_section_header(
                "FUNCTION DECLARATIONS",
                "These function prototypes were extracted from binary analysis",
                use_cpp_cmt
            )
            
            if h_pw:
                h_func_decls_sb.extend([func_decl_header, EOL])
            elif c_pw:
                c_func_decls_sb.extend([func_decl_header, EOL])
                
            sorted_declarations = sorted(list(all_declarations_to_emit))
            for decl_sig in sorted_declarations:
                if h_pw:
                    h_func_decls_sb.extend([decl_sig, EOL])
                elif c_pw:
                    c_func_decls_sb.extend([decl_sig, EOL])

        if emit_g and g_decls_sb:
            # Create global variables header comment
            globals_header = create_section_header(
                "GLOBAL VARIABLES",
                "These global variables were referenced in the decompiled functions",
                use_cpp_cmt
            )
            
            if h_pw:
                h_globals_sb.extend([globals_header, EOL])
                h_globals_sb.extend(g_decls_sb)
            elif c_pw:
                c_globals_sb.extend([globals_header, EOL])
                c_globals_sb.extend(g_decls_sb)

        if h_pw:
            if h_func_decls_sb:
                h_pw.write("".join(h_func_decls_sb))
            if h_globals_sb:
                h_pw.write("".join(h_globals_sb))

        if c_pw:
            if c_func_decls_sb:
                c_pw.write("".join(c_func_decls_sb))
                if c_globals_sb or b_code_sb:
                    c_pw.println()

            if c_globals_sb:
                c_pw.write("".join(c_globals_sb))
                if b_code_sb:
                    c_pw.println()

            if b_code_sb:
                # Create function implementations header comment
                functions_header = create_section_header(
                    "FUNCTION IMPLEMENTATIONS",
                    "Decompiled code from the binary",
                    use_cpp_cmt
                )
                c_pw.write(functions_header)
                c_pw.write("".join(b_code_sb))

        log_message("INFO", "Export completed successfully.")
        return True
    except Exception as e_main:
        log_message("ERROR", "Export failed: {}".format(e_main))
        traceback.print_exc()
        return False
    finally:
        decompiler.dispose()
        if h_pw:
            h_pw.close()
        if c_pw:
            c_pw.close()


def parse_script_args():
    """
    Parse command-line arguments passed to the script using argparse.
    """
    def str_to_bool(value):
        """Convert string to boolean for argparse."""
        if value.lower() in ('true', '1', 'yes', 'on', 'enable', 'enabled'):
            return True
        elif value.lower() in ('false', '0', 'no', 'off', 'disable', 'disabled'):
            return False
        else:
            raise argparse.ArgumentTypeError("Boolean value expected (true/false, 1/0, yes/no, etc.)")
    
    # Create argument parser
    parser = argparse.ArgumentParser(
        description='Ghidra C/C++ Code Exporter - Export decompiled C/C++ code from Ghidra programs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  analyzeHeadless ... -preScript cpp_exporter_headless.py
  analyzeHeadless ... -preScript cpp_exporter_headless.py --output_dir /tmp
  analyzeHeadless ... -preScript cpp_exporter_headless.py --create_header_file true --base_name myprogram
  analyzeHeadless ... -preScript cpp_exporter_headless.py --function_tag_filters "IMPORTANT,CRITICAL" --function_tag_exclude false

Note: This script runs auto-analysis before exporting. Use --run_decompiler_parameter_id true 
for better variable names (may increase processing time).
        """
    )
    
    # Add all arguments using argparse
    parser.add_argument('--output_dir', 
                       type=str, 
                       default='.',
                       help='Output directory path (default: current directory)')
    
    parser.add_argument('--base_name',
                       type=str,
                       default=None,
                       help='Base name for output files (default: program name)')
    
    parser.add_argument('--create_c_file',
                       type=str_to_bool,
                       default=True,
                       help='Create C implementation file (default: true)')
    
    parser.add_argument('--create_header_file',
                       type=str_to_bool,
                       default=False,
                       help='Create header file (default: false)')
    
    parser.add_argument('--use_cpp_style_comments',
                       type=str_to_bool,
                       default=True,
                       help='Use C++ style comments (//) instead of C style (/* */) (default: true)')
    
    parser.add_argument('--emit_type_definitions',
                       type=str_to_bool,
                       default=True,
                       help='Include type definitions in output (default: true)')
    
    parser.add_argument('--emit_referenced_globals',
                       type=str_to_bool,
                       default=True,
                       help='Include global variables referenced by functions (default: true)')
    
    parser.add_argument('--function_tag_filters',
                       type=str,
                       default='',
                       help='Comma-separated list of function tags to filter by (default: none)')
    
    parser.add_argument('--function_tag_exclude',
                       type=str_to_bool,
                       default=True,
                       help='Exclude (vs include) functions matching tag filters (default: true)')
    
    parser.add_argument('--address_set_str',
                       type=str,
                       default=None,
                       help='Address ranges to process, e.g. "0x1000-0x2000,0x3000" (default: all)')
    
    parser.add_argument('--emit_function_declarations',
                       type=str_to_bool,
                       default=True,
                       help='Include function prototypes for referenced functions (default: true)')
    
    parser.add_argument('--include_functions_only',
                       type=str,
                       default=None,
                       help='Include only specific functions (comma-separated list) (default: all)')
    
    parser.add_argument('--run_decompiler_parameter_id',
                       type=str_to_bool,
                       default=True,
                       help='Run Decompiler Parameter ID analysis for better variable names (default: true)')
    
    # Get script arguments from Ghidra
    try:
        script_args = getScriptArgs()  # type: ignore
    except NameError:
        # getScriptArgs() not available (not running in Ghidra), use empty args
        script_args = []
    
    # Convert Ghidra's key-value pairs to argparse format
    # Ghidra passes arguments as: ['key1', 'value1', 'key2', 'value2']
    # We need to convert to: ['--key1', 'value1', '--key2', 'value2']
    argparse_args = []
    i = 0
    while i < len(script_args):
        key = script_args[i]
        if not key.startswith('--'):
            key = '--' + key
        argparse_args.append(key)
        
        # Add value if available
        if i + 1 < len(script_args):
            value = script_args[i + 1]
            argparse_args.append(value)
            i += 2
        else:
            # Key without value - let argparse handle the error
            i += 1
    
    try:
        # Parse arguments using argparse
        args = parser.parse_args(argparse_args)
        
        # Apply parsed arguments to global variables
        globals()['param_output_dir'] = args.output_dir
        globals()['param_base_name'] = args.base_name
        globals()['param_create_c_file'] = args.create_c_file
        globals()['param_create_header_file'] = args.create_header_file
        globals()['param_use_cpp_style_comments'] = args.use_cpp_style_comments
        globals()['param_emit_type_definitions'] = args.emit_type_definitions
        globals()['param_emit_referenced_globals'] = args.emit_referenced_globals
        globals()['param_function_tag_filters'] = args.function_tag_filters
        globals()['param_function_tag_exclude'] = args.function_tag_exclude
        globals()['param_address_set_str'] = args.address_set_str
        globals()['param_emit_function_declarations'] = args.emit_function_declarations
        globals()['param_include_functions_only'] = args.include_functions_only
        globals()['param_run_decompiler_parameter_id'] = args.run_decompiler_parameter_id
        
        # Log applied settings
        for arg_name, arg_value in vars(args).items():
            if arg_value != parser.get_default(arg_name):
                log_message("INFO", "Setting {} = {}".format(arg_name, repr(arg_value)))
        
    except SystemExit as e:
        # argparse calls sys.exit() on help or error
        if e.code == 0:
            # Help was requested
            log_message("INFO", "Help information displayed")
        else:
            # Parse error occurred
            log_message("ERROR", "Argument parsing failed")
            setHeadlessContinuationOption(HeadlessContinuationOption.ABORT)
        sys.exit(e.code)
    except Exception as e:
        log_message("ERROR", "Error parsing arguments: {}".format(str(e)))
        setHeadlessContinuationOption(HeadlessContinuationOption.ABORT)
        sys.exit(1)
    
    # Special handling for base_name - set to program name if not specified
    if globals().get('param_base_name') is None:
        program_name = currentProgram.getName()  # type: ignore
        globals()['param_base_name'] = program_name
        log_message("INFO", "Using program name as base_name: {}".format(program_name))

# Parse command line arguments
parse_script_args()

def main():
    """Main entry point for the script"""
    log_message("INFO", "--- C/C++ Exporter Script ---")
    
    # Ensure we have a valid progra
    # Note: in PyGhidra currentProgram is injected into the namespace
    # not into the globals
    try:
        _ = currentProgram
    except NameError:
        log_message("ERROR", "No program is loaded")
        sys.exit(1)

    program_name = currentProgram.getName() # type: ignore
    log_message("INFO", "Program: {}".format(program_name))
    log_message("INFO", "Output Dir: {}".format(param_output_dir))
    
    # Use program name as base name if none specified
    global param_base_name
    if not param_base_name:
        param_base_name = program_name
    log_message("INFO", "Base Name: {}".format(param_base_name))
    
    # Output file paths
    if param_create_c_file:
        c_file_path = os.path.join(param_output_dir, param_base_name + ".c")
        log_message("INFO", "Creating C file: {}".format(c_file_path))
    if param_create_header_file:
        h_file_path = os.path.join(param_output_dir, param_base_name + ".h")
        log_message("INFO", "Creating header file: {}".format(h_file_path))
    
    # Create and run the monitor
    console_monitor = ConsoleTaskMonitor()
    
    # Run the main export process
    success = run_export_main(
        currentProgram, # type: ignore
        param_output_dir,
        param_base_name,
        param_create_c_file,
        param_create_header_file,
        param_use_cpp_style_comments,
        param_emit_type_definitions,
        param_emit_referenced_globals,
        param_function_tag_filters,
        param_function_tag_exclude,
        param_address_set_str,
        param_emit_function_declarations,
        console_monitor,
        param_include_functions_only
    )
    
    # Exit with appropriate code
    if not success:
        sys.exit(1)

# Execute main function when script is run
if __name__ == "__main__" or 'currentProgram' in globals():
    main()
