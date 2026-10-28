package compiler

/*
 * Options for building one target: a root package, compiled for one architecture and OS
 * into one output.
 *
 * A build package (output type .Nothing) registers targets from #run code with add_target.
 * Start from command_line_options() so a target inherits what was given on the
 * command line, and override only what differs.
 */
BuildOptions :: struct {
    // Name used in error messages ([kernel] ...) and as the default output file name.
    name : string,
    /*
     * Folder of the target's root package, relative to the build package, or absolute,
     * like the canonical PackageInfo.path that subfolders and load_package give.
     */
    root : string,
    // Where the output is written. Empty means the default output folder, using name.
    output_path : string,
    /*
     * The function the target starts in. Empty means main for executables,
     * and no entry for libraries.
     */
    entry : string,
    // Overrides for where imports from "base", "std", etc. are found.
    package_paths : PackagePath[..],
    // Per-target values that the target's code reads with target_setting().
    settings : TargetSetting[..],
    // The typed libraries the target calls (docs/compilation.md, Typed Libraries).
    libraries : LinkedLibrary[..],
    backend_options : BackendOptions,
    configuration : Configuration,
    target_options : TargetOptions,
}

/*
 * A typed library a target calls (docs/compilation.md, Typed Libraries): another target of the build, by its name, or
 * a library built elsewhere, by the folder of its package and its file. The target's code imports the library's package
 * as any other; its #export functions are called through the library.
 */
LinkedLibrary :: struct {
    // A target of this build, an OutputType.DynamicLibrary, whose root and output are used
    target : string,
    // Otherwise the folder of the library's package, relative to the build package, or absolute
    root : string,
    // And the library's file: what the program loads, from beside itself unless it names a folder
    file : string,
}

BackendOptions :: struct {
    backend_type : BackendType,
    optimization_level : OptimizationLevel,
    debug_info : bool,
    llvm_options : LLVMOptions,
}

LLVMOptions :: struct {

}

BackendType :: enum {
    LLVM,
}

Configuration :: enum {
    Debug,
    Release
}

OptimizationLevel :: enum {
    O0,
    O1,
    O2,
    O3,
}

TargetOptions :: struct {
    architecture : Architecture,
    os : OperatingSystem,
    output_type : OutputType,
    // Processor to generate code for. Empty or "generic" uses the architecture's default.
    cpu : string,
    // Comma-separated features to enable or disable, like "+avx2,-sse".
    cpu_features : string,
    code_model : CodeModel,
    relocation_model : RelocationModel,
    // Kernel code needs this off, since interrupts can write below the stack pointer.
    red_zone : bool = true,
    /*
     * Address 0 is memory on this target, like an embedded one's vector table. Accesses to it go
     * through a rawptr (docs/types.md, Pointers), and are kept rather than assumed never to happen.
     */
    address_zero_is_memory : bool = false,
    // Linker script for section placement. Empty uses the linker's default layout.
    linker_script : string,
    // Linker to run. Empty uses the default for the target, see docs/compilation.md (Linking).
    linker : string,
    /*
     * Whether the output includes Hemera's startup code, which sets up the first carrier block
     * and context before calling entry. Freestanding programs like kernels turn this off and
     * do it themselves, with intrinsics.set_carrier and push_context.
     */
    startup_code : bool = true,
    stack_check_failure : StackCheckFailure,
    /*
     * Largest stack frame, in bytes, any function may have. A larger one is a compile error.
     * 0 means no limit. For programs with small fixed stacks, like a kernel.
     */
    max_frame_size : usize,
}

/*
 * What a function does when its prologue stack check finds too little room left. There's no
 * reliable context in a prologue, and only STACK_GUARD bytes of stack, so nothing runs Hemera code
 * there: a trap reaches whatever handles faults, on a stack of its own, like a kernel's.
 */
StackCheckFailure :: enum {
    // Call morestack, which runs the function on a new stack segment. Needs an allocator.
    Morestack,
    // Stop with intrinsics.trap(), for code with one fixed-size stack, like a kernel.
    Trap,
}

/*
 * How far apart code and data may be, which decides how wide the addresses and offsets
 * in instructions are. Separate from RelocationModel, which decides whether they are
 * absolute or relative to the code using them.
 */
CodeModel :: enum {
    // The architecture's usual choice, which is almost always Small.
    Default,
    // All code and static data fit in 2 GiB (4 GiB on arm64), so 32-bit offsets are enough.
    Small,
    // x86_64 only, and only useful without position independence: all code and data are
    // in the top 2 GiB of the address space, so sign-extended 32-bit addresses reach them.
    Kernel,
    // Code fits in 2 GiB, but large data objects can be anywhere and use 64-bit addresses.
    Medium,
    // No assumptions, so 64-bit addresses for everything. Slowest and largest code.
    // Not supported with position independent code on arm64.
    Large,
}

/*
 * Whether addresses are fixed when linking, or relative so the output works wherever
 * it is loaded.
 */
RelocationModel :: enum {
    // PIE for executables, PIC for dynamic libraries, and PIC for static libraries,
    // so they can be linked into either.
    Default,
    // Absolute addresses, so the output must be loaded at the address it was linked for.
    Static,
    // Position independent, for dynamic libraries. Symbols defined elsewhere may be
    // replaced at load time, so they are reached through the global offset table.
    PIC,
    // Position independent, for executables. Every symbol is known to be defined in
    // the executable, so references stay direct.
    PIE,
}

OutputType :: enum {
    DynamicLibrary,
    Executable,
    /*
     * The loadable bytes only, with no headers, laid out by the linker script and meant
     * to be loaded at a fixed address. For boot sectors and firmware images.
     */
    FlatBinary,
    Nothing,
    StaticLibrary,
}

/*
 * Where a built-in import location ("base", "std", "user", "vendor") is found,
 * like --package=std:../my_std on the command line.
 */
PackagePath :: struct {
    location : string,
    path : string,
}

/*
 * Settings are strings rather than any values, because the build package and the
 * target are type checked separately (the target's OS, TARGET_ARCH and #if branches
 * can differ), so a type from one doesn't exist in the other.
 */
TargetSetting :: struct {
    name : string,
    value : string,
}

// A target or step registered by build code, which later steps can depend on.
BuildNode :: distinct alias u32

/*
 * What a step receives for each target it depends on. Steps that a step depends on
 * have no outputs of their own, so they don't appear here.
 */
TargetOutput :: struct {
    node : BuildNode,
    name : string,
    path : string,
    output_type : OutputType,
}

/*
 * Run after everything it depends on has finished. Returning false fails the build,
 * after reporting why with report_error.
 */
StepFunction :: alias fn(inputs: TargetOutput[]) -> bool

/*
 * Run on each target once it has been type checked, before code generation.
 * Errors are reported with report_error, and the check should keep going so every
 * problem is reported. Returning false fails that target.
 */
CheckFunction :: alias fn(target: ptr[BuildOptions], program: ptr[ProgramInfo]) -> bool

/*
 * What compile-time code is allowed to do outside the compiler.
 * By default, neither is allowed. They are granted on the command line (--allow-run),
 * and only to execution the build package started: its own #run code, steps and checks.
 * #run code in other packages always gets neither (docs/compilation.md).
 */
BuildPermissions :: struct {
    run_processes : bool,
    write_outside_output : bool,
}

/*
 * The compiler copies everything it keeps from the values passed to the functions below,
 * so none of their parameters are #escaping, and names and paths can be built in stack buffers.
 */

/*
 * The options given on the command line, as defaults for the targets of a build.
 * name, root and entry are empty, and output_type is the one of the program being compiled.
 */
command_line_options : fn() -> BuildOptions : ---

/*
 * The options of the target currently being compiled. During a build package's own #run code,
 * this is the build package itself.
 */
current_build_options : fn() -> BuildOptions : ---

// Register a target, which is built once the build package has finished compiling.
add_target : fn(options: BuildOptions, location := #caller_location) -> BuildNode : ---

// Register a step, run after everything in after has finished successfully.
add_step : fn(step: StepFunction, after: BuildNode[], location := #caller_location) -> BuildNode : ---

// Every target registered so far.
all_targets : fn() -> BuildNode[] : ---

// Register a check that runs on every target once it has been type checked.
add_check : fn(check: CheckFunction, location := #caller_location) : ---

/*
 * The value of a setting for the target currently being compiled, or default if the
 * target doesn't have that setting.
 */
target_setting : fn(name: string, default := "") -> string : ---

/*
 * What the compile-time code calling this is allowed to do outside the compiler.
 * Nothing is granted outside execution the build package started.
 */
build_permissions : fn() -> BuildPermissions : ---

/*
 * Report a compile error at location, without stopping compile-time execution, so every
 * problem can be reported. The build fails once the current target is done.
 */
report_error : fn(location: SourceCodeLocation, format_string: string, params: any...) : ---

// Report a warning at location, which doesn't fail the build.
report_warning : fn(location: SourceCodeLocation, format_string: string, params: any...) : ---
