package os

import compiler from "base"

ProcessResult :: struct {
    exit_code : int,
    // Everything the process wrote to standard output, allocated with context.allocator.
    output : string,
    // Everything the process wrote to standard error, allocated with context.allocator.
    error_output : string,
}

ProcessError :: enum {
    // Running processes at compile time needs --allow-run on the command line.
    NotPermitted,
    // program wasn't found, or isn't executable.
    NotFound,
    // The program was found, but the OS couldn't start it.
    FailedToStart,
    // The target has no processes, like OS == .None.
    Unsupported,
}

/*
 * Run program with arguments, wait for it to finish, and return its exit code and output.
 * working_directory defaults to the current one.
 *
 * Works at compile time too, for build steps that need an external tool, but only when
 * the command line grants it with --allow-run. Otherwise this reports a compile error at
 * the caller and returns NotPermitted, so each caller doesn't have to check.
 */
run_process :: fn(
    program: string,
    arguments: string[],
    working_directory: string? = null,
    location := #caller_location,
) -> Result[ProcessResult, ProcessError] {
    if #is_compile_time && !compiler.build_permissions().run_processes {
        compiler.report_error(location,
            "running % at compile time needs --allow-run on the command line", program)
        return Result::Error(ProcessError.NotPermitted)
    }
    //TODO start the process and collect its output
    return Result::Error(ProcessError.Unsupported)
}
