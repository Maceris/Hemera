/*
 * std/os's run_process: a shell that writes to standard output and error and exits with a code, a program that isn't
 * there, arguments with spaces and quotes, and a working directory. It keeps its own main, as it runs itself again as
 * the child that gives its arguments back; main runs the tests and returns 42 if they all passed, or 1.
 */
package processes_test

import compiler from "base"
import os from "std"
import runtime from "base"
import strings from "std"
import testing from "std"

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

runs_a_shell_and_keeps_its_output_and_exit_code #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    result :: testing.require_ok(t, os.run_process(SHELL, string.[FLAG, BOTH]), "the system's shell is there to run")?
    testing.expect_eq(t, result.exit_code, 3, "the shell exits with the code its command gave")
    testing.expect_eq(t, strings.trim(result.output), "out", "what it wrote to standard output is kept apart")
    testing.expect_eq(t, strings.trim(result.error_output), "err", "what it wrote to standard error is kept apart")
    return .Ok
}

refuses_a_program_that_isnt_there #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    missing :: os.run_process("no_such_program_anywhere", string.[])
    testing.expect_error(t, missing, .NotFound, "no program by that name is anywhere on the path")
    return .Ok
}

passes_arguments_as_they_were_given #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Arguments that need quoting arrive as they were given: this program, run again, gives them back
    arguments :: os.arguments()
    testing.require(t, arguments.count > 0, "a program is given its own path, to run itself again")?
    if arguments.count == 0 {
        return .Ok
    }
    given : string[..]
    runtime.array_add(&given, "--echo")
    for argument in TRICKY {
        runtime.array_add(&given, argument)
    }
    echoed :: os.run_process(arguments[0], given)
    runtime.array_free(&given)
    result :: testing.require_ok(t, echoed, "this program runs again")?
    testing.expect_eq(t, result.output, "[a \"b c\"][][x \\][plain]", "spaces, quotes, nothing and a trailing backslash each come through as one argument")
    return .Ok
}

/**
 * Run as the child, give back the arguments after --echo, each in brackets; otherwise run the tests.
 *
 * @return 0 as the child; as the tests' runner, 42 if every test passed, or 1.
 */
main :: fn() -> int {
    arguments :: os.arguments()
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
    if testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.STANDARD_OUTPUT) != 0 {
        return 1
    }
    return 42
}
