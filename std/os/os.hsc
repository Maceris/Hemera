package os

import runtime from "base"

/**
 * End the process at once, every thread of it, from any thread.
 *
 * Nothing else runs: no deferred code, no other thread, and in a program that links C, C's buffered streams aren't
 * flushed. On a target without processes, like a kernel (OS == .None), it traps. Under UEFI it returns to whoever
 * started the program, through the boot services' Exit.
 *
 * @param code The exit code. On Linux the parent sees only its low 8 bits; on Windows all 32. Under UEFI, 0 gives
 *     EFI_SUCCESS and anything else EFI_ABORTED, the code itself lost. Where there's no process, it goes nowhere.
 */
exit :: fn(code: u32) #never_returns {
    runtime.os_exit_process(code)
}
