/*
 * For hemera --diagnostics=json: compile-time code that prints through base and through C, beside a warning. Only the
 * warning, as JSON, may reach standard output, which is kept for diagnostics; the prints go to standard error.
 */
package main

import compiler from "base:compiler"
import runtime from "base:runtime"

UCRT :: #library("ucrtbase")
puts #foreign(UCRT) : fn(text : rawptr) -> i32 : ---
fflush #foreign(UCRT) : fn(stream : rawptr) -> i32 : ---

print_both :: fn() -> int {
    runtime.write_output("printed through base\n")
    text :: "printed through C\0"
    puts(cast[rawptr](text.data))
    // C buffers what isn't a console, and its library's buffers aren't flushed when the compiler exits
    fflush(null)
    compiler.report_warning(#source_location, "a \"quoted\" warning")
    return 0
}

PRINTED :: #run print_both()

main :: fn() -> int {
    return PRINTED
}
