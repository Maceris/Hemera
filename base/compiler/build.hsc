package compiler

/**
 * Options for building one target: a root package, compiled for one architecture and OS
 * into one output.
 *
 * A build package (output type .Nothing) registers targets from #run code with add_target.
 * Start from command_line_options() so a target inherits what was given on the
 * command line, and override only what differs.
 */
BuildOptions :: struct {
    /**
     * Name used in error messages ([kernel] ...), as the default output file name, and by which a LinkedLibrary or a
     * TargetOutput names the target. Empty from command_line_options.
     */
    name : string,
    /**
     * Folder of the target's root package, relative to the build package, or absolute,
     * like the canonical PackageInfo.path that subfolders and load_package give.
     */
    root : string,
    /**
     * Where the output is written, relative to the build package's folder; every file made from it is named after it,
     * with its own extension. Empty means the default output folder, using name.
     */
    output_path : string,
    /**
     * The function the target starts in. Empty means main for executables,
     * and no entry for libraries.
     */
    entry : string,
    /**
     * Whether the target is a test program: its root package's #test functions run, and are reported to standard
     * output, in place of entry, as hemera --test builds one (docs/testing.md).
     */
    test : bool,
    /** With test, only the tests whose names contain this are run; empty runs them all. */
    test_filter : string,
    /**
     * With test, which tags' tests are run, as words separated by commas, like "+slow,-network", as
     * testing.RunOptions.tags says; empty runs each test none of whose tags is left out by default.
     */
    test_tags : string,
    /** With test and test_seeded, the seed every property test draws its cases from; otherwise not used. */
    test_seed : u64,
    /** With test, whether test_seed is given; without it, each property test has its own seed, from its name. */
    test_seeded : bool,
    /** With test, how many cases each property test draws; 0 for testing.DEFAULT_RUNS. */
    test_runs : u64,
    /** Overrides for where imports from "base", "std", etc. are found; empty uses the compiler's own. */
    package_paths : PackagePath[..],
    /**
     * Per-target values that the target's code reads with target_setting(). From command_line_options, those given on
     * the command line; a later one of the same name wins.
     */
    settings : TargetSetting[..],
    /** The typed libraries the target calls (docs/compilation.md, Typed Libraries); empty for none. */
    libraries : LinkedLibrary[..],
    /** How code is generated: the optimization level and debug info. */
    backend_options : BackendOptions,
    /**
     * Whether the target is built for debugging or for release, which its code reads with current_build_options.
     * command_line_options gives Debug when the options have debug info, and Release otherwise. It changes nothing
     * about the code generated, which backend_options decides, so a release build can still have debug info.
     */
    configuration : Configuration,
    /** What the target is compiled for and how it's linked. */
    target_options : TargetOptions,
}

/**
 * A typed library a target calls (docs/compilation.md, Typed Libraries): another target of the build, by its name, or
 * a library built elsewhere, by the folder of its package and its file. The target's code imports the library's package
 * as any other; its #export functions are called through the library.
 */
LinkedLibrary :: struct {
    /** A target of this build, by its name, an OutputType.DynamicLibrary, whose root and output are used; or empty. */
    target : string,
    /** When target is empty, the folder of the library's package, relative to the build package, or absolute. */
    root : string,
    /**
     * When target is empty, the library's file: what the program loads, from beside itself unless it names a
     * folder.
     */
    file : string,
}

/** How a target's code is generated. */
BackendOptions :: struct {
    /** Which code generator: only LLVM so far. */
    backend_type : BackendType,
    /** How much the optimizer does; O2 unless the command line says otherwise. */
    optimization_level : OptimizationLevel,
    /**
     * Whether the output has debug info (--debug, docs/compilation.md, Debug Info): DWARF or CodeView, and the table
     * of functions' names stack traces use.
     */
    debug_info : bool,
    /** LLVM's own options, of which there are none yet. */
    llvm_options : LLVMOptions,
}

/** LLVM's own options for a target, of which there are none yet. */
LLVMOptions :: struct {

}

/** The code generators a target can be built with. */
BackendType :: enum {
    /** LLVM, the only one. */
    LLVM,
}

/**
 * Whether a build is for debugging or for release: what a build package gives its target, or from the command line,
 * whether it has debug info.
 */
Configuration :: enum {
    /** For debugging: what the command line gives with debug info. */
    Debug,
    /** For release: what the command line gives without debug info. */
    Release
}

/** How much the optimizer does, as LLVM's levels. */
OptimizationLevel :: enum {
    /** No optimization: fastest to compile, and easiest to debug. */
    O0,
    /** Light optimization. */
    O1,
    /** The usual optimization, the command line's default. */
    O2,
    /** The most optimization, trading size and compile time for speed. */
    O3,
}

/** What a target is compiled for, and how it's linked and started. */
TargetOptions :: struct {
    /** The processor architecture, which TARGET_ARCH is in the target's code. */
    architecture : Architecture,
    /** The operating system, which OS is in the target's code; None also makes the output ELF. */
    os : OperatingSystem,
    /** What kind of file is made. */
    output_type : OutputType,
    /** Processor to generate code for. Empty or "generic" uses the architecture's default. */
    cpu : string,
    /** Comma-separated features to enable or disable, like "+avx2,-sse". Empty leaves the cpu's own. */
    cpu_features : string,
    /** How far apart code and data may be. */
    code_model : CodeModel,
    /** Whether addresses are fixed when linking or relative. */
    relocation_model : RelocationModel,
    /**
     * Whether functions may use the 128 bytes below the stack pointer without moving it, on x86-64. Kernel code needs
     * this off, since interrupts can write below the stack pointer.
     */
    red_zone : bool = true,
    /**
     * Address 0 is memory on this target, like an embedded one's vector table. Accesses to it go
     * through a rawptr (docs/types.md, Pointers), and are kept rather than assumed never to happen.
     */
    address_zero_is_memory : bool = false,
    /**
     * Hardware control-flow integrity (docs/compilation.md, Control-Flow Integrity): a landing pad at every function's
     * entry and after every call (endbr64 on x86-64, bti on AArch64), return addresses signed on AArch64 (pac-ret),
     * and ELF notes saying the code has them and works with shadow stacks and the Guarded Control Stack. Each is a no-op
     * on a CPU without it. ELF targets only.
     */
    control_flow_integrity : bool = false,
    /**
     * Coverage counters, as hemera --fuzz builds a program with (docs/testing.md, Fuzzing): a counter for each basic
     * block, bumped as it runs, and the constants it compares with, which intrinsics.coverage_counters and
     * coverage_constants give; for a fuzzer that reads another program's coverage, like an operating system's kernel's.
     */
    coverage : bool = false,
    /**
     * Linker script for section placement, relative to the build package's folder. Empty uses the linker's default
     * layout.
     */
    linker_script : string,
    /**
     * Folders the linker looks in for the libraries #foreign functions come from, before its own, relative to the
     * build package's folder. Those given on the command line with --library-path come after them.
     */
    library_paths : string[..],
    /**
     * Linker to run: a program's name, found on the PATH, or, when it has a / or \ in it, its path, relative to the
     * build package's folder. It's given the default's arguments, lld-link's for PE/COFF and ld.lld's for ELF, so it
     * has to take those. Empty uses the default (docs/compilation.md, Linking).
     */
    linker : string,
    /**
     * Whether the output includes Hemera's startup code, which sets up the first carrier block
     * and context before calling entry. Freestanding programs like kernels turn this off and
     * do it themselves, with intrinsics.set_carrier and push_context.
     */
    startup_code : bool = true,
    /** What a function's prologue does when its stack check finds too little room. */
    stack_check_failure : StackCheckFailure,
    /**
     * Largest stack frame, in bytes, any function may have; a larger one is a compile error (E6001) naming the
     * function. 0 means no limit. For programs with small fixed stacks, like a kernel. Frames are measured as the
     * machine code is generated, so after optimization, at the target's optimization_level.
     */
    max_frame_size : usize,
}

/**
 * What a function does when its prologue stack check finds too little room left. There's no
 * reliable context in a prologue, and only STACK_GUARD bytes of stack, so nothing runs Hemera code
 * there: a trap reaches whatever handles faults, on a stack of its own, like a kernel's.
 */
StackCheckFailure :: enum {
    /** Call morestack, which runs the function on a new stack segment. Needs an allocator. */
    Morestack,
    /** Stop with intrinsics.trap(), for code with one fixed-size stack, like a kernel. */
    Trap,
}

/**
 * How far apart code and data may be, which decides how wide the addresses and offsets
 * in instructions are. Separate from RelocationModel, which decides whether they are
 * absolute or relative to the code using them.
 */
CodeModel :: enum {
    /** The architecture's usual choice, which is almost always Small. */
    Default,
    /** All code and static data fit in 2 GiB (4 GiB on arm64), so 32-bit offsets are enough. */
    Small,
    /**
     * x86_64 only, and only useful without position independence: all code and data are
     * in the top 2 GiB of the address space, so sign-extended 32-bit addresses reach them.
     */
    Kernel,
    /** Code fits in 2 GiB, but large data objects can be anywhere and use 64-bit addresses. */
    Medium,
    /**
     * No assumptions, so 64-bit addresses for everything. Slowest and largest code.
     * Not supported with position independent code on arm64.
     */
    Large,
}

/**
 * Whether addresses are fixed when linking, or relative so the output works wherever
 * it is loaded.
 */
RelocationModel :: enum {
    /**
     * PIE for executables, PIC for dynamic libraries, and PIC for static libraries,
     * so they can be linked into either.
     */
    Default,
    /** Absolute addresses, so the output must be loaded at the address it was linked for. */
    Static,
    /**
     * Position independent, for dynamic libraries. Symbols defined elsewhere may be
     * replaced at load time, so they are reached through the global offset table.
     */
    PIC,
    /**
     * Position independent, for executables. Every symbol is known to be defined in
     * the executable, so references stay direct.
     */
    PIE,
}

/** What kind of file a target makes. */
OutputType :: enum {
    /** A library loaded when a program runs, a DLL or a shared object, as a typed library is. */
    DynamicLibrary,
    /** A program to run, starting at its entry. */
    Executable,
    /**
     * The loadable bytes only, with no headers, laid out by the linker script and meant
     * to be loaded at a fixed address. For boot sectors and firmware images.
     */
    FlatBinary,
    /** No output: a build package, whose compile-time code registers the targets. */
    Nothing,
    /** An archive of object files, for linking into other programs. */
    StaticLibrary,
}

/**
 * Where a built-in import location ("base", "std", "user", "vendor") is found,
 * like --package=std:../my_std on the command line.
 */
PackagePath :: struct {
    /** The import location's name, like "std", without quotes. */
    location : string,
    /** The folder it's found in, relative to the build package's folder, or absolute. */
    path : string,
}

/**
 * Settings are strings rather than any values, because the build package and the
 * target are type checked separately (the target's OS, TARGET_ARCH and #if branches
 * can differ), so a type from one doesn't exist in the other.
 */
TargetSetting :: struct {
    /** What target_setting looks it up by. */
    name : string,
    /** What target_setting gives for it, which the target's code parses as it needs. */
    value : string,
}

/**
 * A target or step registered by build code, which later steps can depend on: a number the compiler gives each in
 * turn, from add_target and add_step.
 */
BuildNode :: distinct alias u32

/**
 * What a step receives for each target it depends on. Steps that a step depends on
 * have no outputs of their own, so they don't appear here.
 */
TargetOutput :: struct {
    /** The target, as add_target gave it. */
    node : BuildNode,
    /** The target's name, from its BuildOptions. */
    name : string,
    /** Where its output was written. */
    path : string,
    /** What kind of file it is. */
    output_type : OutputType,
}

/**
 * A step's function: run after everything it depends on has finished.
 *
 * @param inputs The output of each target it depends on; steps it depends on have no outputs, so they aren't here.
 * @return True to go on; false fails the build, after reporting why with report_error.
 */
StepFunction :: alias fn(inputs: TargetOutput[]) -> bool

/**
 * A check's function: run on each target once it has been type checked, before code generation.
 * Errors are reported with report_error, and the check should keep going so every
 * problem is reported.
 *
 * @param target The options the target is built with, written out once for its checks; every check on it is given the
 *     same copy, so changing it changes nothing about the build.
 * @param program The target's whole program; its values have the target's types, compared by name (see ConstantInfo).
 * @return True when the target passes; false fails that target, as reporting an error does.
 */
CheckFunction :: alias fn(target: ptr[BuildOptions], program: ptr[ProgramInfo]) -> bool

/**
 * What compile-time code is allowed to do outside the compiler.
 * By default, neither is allowed. They are granted on the command line (--allow-run),
 * and only to execution the build package started: its own #run code, steps and checks.
 * #run code in other packages always gets neither (docs/compilation.md).
 */
BuildPermissions :: struct {
    /** Whether it may run other programs, as os.run_process does. */
    run_processes : bool,
    /** Whether it may write files outside the output folder. */
    write_outside_output : bool,
}

/*
 * The compiler copies everything it keeps from the values passed to the functions below,
 * so none of their parameters are #escaping, and names and paths can be built in stack buffers.
 */

/**
 * Give the options given on the command line, as defaults for the targets of a build.
 *
 * @return The options, with name, root and entry empty and output_type .Executable, so a target only sets what
 *     differs. Its settings are those the command line gave.
 */
command_line_options : fn() -> BuildOptions : ---

/**
 * Give the options of the target currently being compiled.
 *
 * @return The target's options, with its name, entry and output path. During a build package's own #run code, they're
 *     the build package's own.
 */
current_build_options : fn() -> BuildOptions : ---

/**
 * Register a target, which is built once the build package has finished compiling.
 *
 * @param options The target's options, copied, so they can be changed or reused after.
 * @param location Where the target is reported as registered, for its errors; the caller's own by default.
 * @return The target's node, for steps to depend on.
 */
add_target : fn(options: BuildOptions, location := #caller_location) -> BuildNode : ---

/**
 * Register a step, run after everything in after has finished successfully; steps run once every target is done.
 *
 * @param step The function to run, given the outputs of the targets in after. Returning false fails the build.
 * @param after The targets and steps it waits for, copied.
 * @param location Where the step is reported as registered; the caller's own by default.
 * @return The step's node, for later steps to depend on.
 */
add_step : fn(step: StepFunction, after: BuildNode[], location := #caller_location) -> BuildNode : ---

/**
 * Give every target registered so far.
 *
 * @return Their nodes, in the order they were registered; empty before the first add_target. A copy: targets added
 *     later aren't in it.
 */
all_targets : fn() -> BuildNode[] : ---

/**
 * Register a check that runs on every target once it has been type checked, before code generation.
 *
 * @param check The function to run, given the target's options and its whole program. Returning false, or reporting
 *     an error, stops that target.
 * @param location Where the check is reported as registered; the caller's own by default.
 */
add_check : fn(check: CheckFunction, location := #caller_location) : ---

/**
 * Give the value of a setting for the target currently being compiled.
 *
 * @param name The setting's name, compared exactly.
 * @param default What to give when the target doesn't have that setting.
 * @return The setting's value, the last one given if it was given more than once; default if it wasn't given.
 */
target_setting : fn(name: string, default := "") -> string : ---

/**
 * Give what the compile-time code calling this is allowed to do outside the compiler.
 *
 * @return Both granted when the command line gave --allow-run and the build package started this execution; neither
 *     otherwise, as in #run code of any other package.
 */
build_permissions : fn() -> BuildPermissions : ---

/**
 * Report a compile error at location, without stopping compile-time execution, so every
 * problem can be reported. The build fails once the current target is done.
 *
 * @param location Where the error is reported, like #caller_location for an error in what the caller gave.
 * @param format_string The message, with placeholders (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 */
report_error : fn(location: SourceCodeLocation, format_string: string, params: any...) : ---

/**
 * Report a warning at location, which doesn't fail the build.
 *
 * @param location Where the warning is reported.
 * @param format_string The message, with placeholders (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 */
report_warning : fn(location: SourceCodeLocation, format_string: string, params: any...) : ---
