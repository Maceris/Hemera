package os

import compiler from "base"
import runtime from "base"

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
 * Run program with arguments, wait for it to finish, and return its exit code and what it wrote to
 * standard output and standard error, from context.allocator. program is looked for on the PATH when
 * it's only a name. working_directory defaults to the current one. Standard input is closed.
 *
 *     match os.run_process("git", string.["rev-parse", "HEAD"]) {
 *         case Ok(result) => commit = strings.trim(result.output)
 *         case Error(error) => runtime.log_error("can't run git: %", error)
 *     }
 *
 * At compile time, for build steps that need an external tool, it's allowed only when the command
 * line grants it with --allow-run. Otherwise this reports a compile error at the caller and returns
 * NotPermitted, so each caller doesn't have to check.
 */
run_process :: fn(
    program: string,
    arguments: string[],
    working_directory: string? = null,
    location := #caller_location,
) -> Result[ProcessResult, ProcessError] #unrestricted {
    if #is_compile_time && !compiler.build_permissions().run_processes {
        compiler.report_error(location,
            "running % at compile time needs --allow-run on the command line", program)
        return .Error(.NotPermitted)
    }
    result, error :: system_run_process(program, arguments, working_directory, context.allocator)
    match error {
        case Some(failure) => return .Error(failure)
        case None => return .Ok(result)
    }
}

// Bytes added to a growing buffer, for what a process writes.
append_bytes :: fn(buffer: ptr[mut u8[..]], bytes: rawptr, count: usize) {
    for i in 0..<count {
        runtime.array_add(buffer, cast[ptr[u8]](bytes + i)^)
    }
}

// A buffer's bytes as a string, which then owns them.
as_text :: fn(buffer #escaping : u8[..]) -> string #unrestricted {
    if buffer.count == 0 {
        return ""
    }
    return string_of(cast[ptr[u8]](buffer.data), buffer.count)
}
