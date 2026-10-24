package slop_os_program

import runtime from "base"

/*
 * A program for SlopOS, built but not run here: its heap maps memory in the range its startup block
 * gives, and main's result is the process's exit code.
 */
main :: fn() -> int {
    values, error :: runtime.new_array(u64, 100)
    if error != null {
        return 1
    }
    defer runtime.free_array(values)
    for &value, i in values {
        value^ = cast[u64](i)
    }
    return 0
}
