/*
 * For hemera --check: what generating would run at compile time, a check runs too, by reaching what generating would
 * reach, and nothing else. Each warning says what ran.
 */
package main

import compiler from "base:compiler"

// Worked out by running it, once code using it is reached
limit :: fn() -> int {
    compiler.report_warning(#source_location, "LIMIT was worked out")
    return 3
}

LIMIT :: limit()

// Nothing reached uses it, so it isn't worked out
unused_limit :: fn() -> int {
    compiler.report_warning(#source_location, "UNUSED was worked out")
    return 4
}

UNUSED :: unused_limit()

// Named by a constant that isn't run, whose value is walked for what it names
Handler :: struct {
    handle : fn() -> int,
}

handled :: fn() -> int {
    #run compiler.report_warning(#source_location, "handled was reached through HANDLER")
    return 0
}

HANDLER :: Handler.{handle = handled}

// Reached through main's call
helper :: fn() -> int {
    #run compiler.report_warning(#source_location, "helper was reached")
    return LIMIT + #run limit_twice()
}

limit_twice :: fn() -> int {
    compiler.report_warning(#source_location, "a #run expression ran")
    return 6
}

// Not reached, so what it runs doesn't run
unreached :: fn() -> int {
    #run compiler.report_warning(#source_location, "unreached was reached")
    return 1
}

main :: fn() -> int {
    return helper() + HANDLER.handle() - 9
}
