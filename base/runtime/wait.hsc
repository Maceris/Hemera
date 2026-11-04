package runtime

import intrinsics from "base"

/*
 * Sleeping until a 32-bit value changes, for code like a fiber pool's carriers with nothing to run:
 *
 *     wait_on_value(address, expected)   // returns once address^ isn't expected, or spuriously
 *     wake_one(address), wake_all(address)
 *
 * A wait whose value already changed returns at once. Without an operating system to sleep on,
 * waiting just spins once, so callers loop the same either way.
 */
// Windows' are in windows.hsc, Linux's on x86-64 and AArch64 in linux.hsc, and SlopOS's in slop_os_threads.hsc
#if OS != .Windows && !(OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64))
    && !(OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) {
    /**
     * Wait until the value at address isn't expected: here, without a system to sleep on, a spin hint and a return,
     * which callers looping on the value can't tell from a spurious wake.
     *
     * @param address The value to watch, which another thread or fiber changes; it isn't read here.
     * @param expected The value it had when the caller decided to wait.
     */
    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        intrinsics.spin_hint()
    }

    /**
     * Wake one waiter sleeping on the value at address: here, with nothing ever asleep, nothing to do.
     *
     * @param address The value waited on.
     */
    wake_one :: fn(address: ptr[u32]) {}

    /**
     * Wake every waiter sleeping on the value at address: here, with nothing ever asleep, nothing to do.
     *
     * @param address The value waited on.
     */
    wake_all :: fn(address: ptr[u32]) {}

    /**
     * Start a thread on the system: here it can't, since threads don't start on this system yet.
     *
     * @param thread The thread, which is left as it is.
     * @return Always false: the thread wasn't started.
     */
    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        return false
    }

    /**
     * Wait for a thread to finish: here nothing, since no thread can have started.
     *
     * @param thread The thread, which is left as it is.
     */
    os_thread_join :: fn(thread: ptr[mut Thread]) {}

    /**
     * Fetch the program's command-line arguments: here there's no command line, so none.
     *
     * @param allocator Where the arguments would be allocated; nothing is.
     * @return An empty array, which needs no freeing.
     */
    os_command_line_arguments :: fn(allocator: Allocator) -> string[] {
        empty : string[]
        return empty
    }

}

#if OS != .Windows && !(OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) && !(OS == .SlopOS && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64))
    && OS != .UEFI {
    /**
     * Write bytes to standard output or error: here there's neither, so they're dropped.
     *
     * @param stream Which stream the bytes were for.
     * @param bytes The bytes, which aren't read.
     * @param count How many bytes there are.
     */
    os_write #no_context :: fn(stream: OutputStream, bytes: rawptr, count: usize) {}

    /**
     * End the process: here, with no system to return to, by trapping.
     *
     * @param code The exit code, which goes nowhere.
     */
    os_exit_process #no_context :: fn(code: u32) #never_returns {
        intrinsics.trap()
    }

    /** What a hosted program's main starts with: here MINIMAL_CONTEXT, with no heap, logger or clock. */
    HOSTED_CONTEXT :: MINIMAL_CONTEXT
}
