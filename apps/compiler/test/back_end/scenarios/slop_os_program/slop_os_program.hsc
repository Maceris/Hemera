package slop_os_program

import runtime from "base"

/*
 * A program for SlopOS, built but not run here: its heap maps memory in the range its startup block
 * gives, and main's result is the process's exit code. It logs a usize, whose schema the SlopOS logger writes. Its
 * entry takes values, which the runtime reads from its grant "arguments".
 */
main :: fn(count: usize, label: string, verbose: bool?) -> int {
    values, error :: runtime.new_array(u64, count)
    if error != null {
        return 1
    }
    defer runtime.free_array(values)
    for &value, i in values {
        value^ = cast[u64](i)
    }
    runtime.log_info("% values for %, verbose %", values.count, label, verbose or_else false)
    return 0
}
