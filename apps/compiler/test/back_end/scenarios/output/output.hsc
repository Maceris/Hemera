/*
 * A hosted program that writes to standard output and error, through std/io and the standard
 * logger the hosted context starts with. The test checks what it wrote: output.txt and error.txt
 * next to this file. main returns 42.
 */
package output_test

import runtime from "base"
import io from "std"

Color :: enum {
    RED,
    GREEN,
}

main :: fn() -> int {
    io.print("hello, ")
    io.println("world")
    count : u32 = 3
    io.printf("% files, % bytes, %\n", count, -12, true)
    io.eprintln("to standard error")
    runtime.log_info("loaded % files in %", count, "1 pass")
    // Below the hosted context's level, INFO
    runtime.log_debug("not shown")
    runtime.log_warn("% is %, %%", Color.GREEN, 7, false)
    push_context quiet (log_level = .ERROR) {
        runtime.log_warn("not shown either")
        runtime.log_error("only errors: %", cast[i8](-5))
    }
    return 42
}
