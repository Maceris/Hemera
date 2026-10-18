package os

import runtime from "base"

/*
 * Ends the process at once with code, from any thread: nothing else runs, so C's buffered streams,
 * in a program that links C, aren't flushed. On a target without processes, like a kernel, it traps.
 */
exit :: fn(code: u32) #never_returns {
    runtime.os_exit_process(code)
}
