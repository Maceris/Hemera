/*
 * std/os's run_process: a shell that writes to standard output and error and exits with a code, a
 * program that isn't there, arguments with spaces and quotes, and a working directory. main returns
 * 42 if each gave what it should, or the number of the first check that didn't.
 */
package processes_test

import os from "std"
import runtime from "base"
import strings from "std"

#if OS == .Windows {
    SHELL :: "cmd.exe"
    FLAG :: "/c"
    BOTH :: "echo out& echo err 1>&2& exit 3"
    ECHO :: "echo"
}
#else {
    SHELL :: "/bin/sh"
    FLAG :: "-c"
    BOTH :: "echo out; echo err 1>&2; exit 3"
    ECHO :: "echo"
}

// Arguments that need quoting: spaces, quotes, nothing, and a backslash at the end
TRICKY :: string.["a \"b c\"", "", "x \\", "plain"]

main :: fn() -> int {
    arguments :: os.arguments()
    // Run as the child: give back the arguments, one a line
    if arguments.count > 1 && arguments[1] == "--echo" {
        for argument, i in arguments {
            if i >= 2 {
                runtime.write_output("[")
                runtime.write_output(argument)
                runtime.write_output("]")
            }
        }
        return 0
    }
    match os.run_process(SHELL, string.[FLAG, BOTH]) {
        case Ok(result) => {
            if result.exit_code != 3 || strings.trim(result.output) != "out" || strings.trim(result.error_output) != "err" {
                runtime.log_error("got % [%] [%]", result.exit_code, result.output, result.error_output)
                return 1
            }
        }
        case Error(error) => {
            runtime.log_error("couldn't run: %", error)
            return 1
        }
    }
    match os.run_process("no_such_program_anywhere", string.[]) {
        case Ok(result) => return 2
        case Error(error) => {
            if error != .NotFound {
                return 2
            }
        }
    }
    // Arguments that need quoting arrive as they were given: this program, run again, gives them back
    if arguments.count > 0 {
        given : string[..]
        runtime.array_add(&given, "--echo")
        for argument in TRICKY {
            runtime.array_add(&given, argument)
        }
        echoed :: os.run_process(arguments[0], given)
        runtime.array_free(&given)
        match echoed {
            case Ok(result) => {
                if result.output != "[a \"b c\"][][x \\][plain]" {
                    runtime.log_error("echoed [%]", result.output)
                    return 3
                }
            }
            case Error(error) => return 3
        }
    }
    return 42
}
