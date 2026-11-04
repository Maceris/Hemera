package os

import compiler from "base"
import runtime from "base"

/** What a process run by run_process left behind: how it ended, and everything it wrote. */
ProcessResult :: struct {
    /**
     * How it ended: the code it exited with, 0 usually meaning success. On Linux, the low 8 bits of its exit status,
     * 0 to 255, or 128 plus the signal's number if a signal killed it, as shells give; on Windows, its whole 32-bit
     * exit code, from 0 to 4294967295 (an NTSTATUS like 0xC0000005 when it crashed).
     */
    exit_code : int,
    /**
     * Everything the process wrote to standard output, as bytes, not checked to be UTF-8; allocated with
     * context.allocator, which the caller owns and frees. Empty, owning nothing, if it wrote nothing.
     */
    output : string,
    /**
     * Everything the process wrote to standard error, as bytes, not checked to be UTF-8; allocated with
     * context.allocator, which the caller owns and frees. Empty, owning nothing, if it wrote nothing.
     */
    error_output : string,
}

/** Why run_process couldn't run a program. */
ProcessError :: enum {
    /** Running processes at compile time needs --allow-run on the command line. */
    NotPermitted,
    /** The program wasn't found: nothing is at its path, or no folder on the PATH has it. */
    NotFound,
    /**
     * The program was found, but the OS couldn't start it: it isn't executable, a pipe or the process couldn't be
     * made, or on Windows the working directory doesn't exist.
     */
    FailedToStart,
    /** The target has no processes to run, like OS == .None or SlopOS, whose programs start through launch. */
    Unsupported,
}

/**
 * Run a program, wait for it to finish, and give back its exit code and what it wrote.
 *
 * Its standard output and error are read as it runs, both at once, so a program that fills one while the other is
 * being waited on can't stall. On Windows it has no standard input; on Linux it shares the caller's.
 *
 *     match os.run_process("git", string.["rev-parse", "HEAD"]) {
 *         case Ok(result) => commit = strings.trim(result.output)
 *         case Error(error) => runtime.log_error("can't run git: %", error)
 *     }
 *
 * At compile time, for build steps that need an external tool, it's allowed only when the command line grants it
 * with --allow-run. Otherwise this reports a compile error at the caller and returns NotPermitted, so each caller
 * doesn't have to check.
 *
 * @param program The program: a path, or only a name, which is looked for on the PATH. On Linux, a name without a '/'
 *     is tried in each folder of the PATH in turn, an empty entry being the current folder, or in /usr/bin and the
 *     current folder without a PATH; on Windows, CreateProcessW looks for it, adding ".exe" when it has no extension.
 * @param arguments The arguments after the program's name, each passed as it is: on Linux as execve takes them, on
 *     Windows quoted so the C runtime's splitting gives each back whole. May be empty.
 * @param working_directory The folder the program starts in, or null for the caller's current directory. On Linux,
 *     one that can't be entered is ignored, and the program starts in the caller's.
 * @param location Where the call is, for the compile error when running isn't allowed; left as the caller's.
 * @return The exit code and the output, which the caller owns (ProcessResult). A program that ran and failed is
 *     still Ok, with its exit code.
 * @error NotPermitted At compile time without --allow-run; a compile error has been reported too.
 * @error NotFound The program wasn't found: on Linux, no path tried has anything at it.
 * @error FailedToStart The OS couldn't start it: what was found isn't executable, pipes or the process couldn't be
 *     made, or on Windows working_directory doesn't exist.
 * @error Unsupported The target has no processes to run, like OS == .None or SlopOS.
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

/**
 * Add bytes to a growing buffer, for what a process writes.
 *
 * @param buffer The buffer, grown with the context's allocator as it needs.
 * @param bytes Where the bytes are, which are copied; only read.
 * @param count How many bytes to add, which may be 0.
 */
append_bytes :: fn(buffer: ptr[mut u8[..]], bytes: rawptr, count: usize) {
    for i in 0..<count {
        runtime.array_add(buffer, cast[ptr[u8]](bytes + i)^)
    }
}

/**
 * Turn a buffer's bytes into a string, which then owns them.
 *
 * @param buffer The buffer, which is moved into the string: it isn't freed or used after.
 * @return Its bytes as a string, owning the buffer's memory, freed as a string from the allocator the buffer grew
 *     with; "" for an empty buffer, owning nothing.
 */
as_text :: fn(buffer #escaping : u8[..]) -> string #unrestricted {
    if buffer.count == 0 {
        return ""
    }
    return string_of(cast[ptr[u8]](buffer.data), buffer.count)
}
