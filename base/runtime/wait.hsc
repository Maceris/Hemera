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
// Windows' are in windows.hsc, and Linux's on x86-64 in linux.hsc
#if OS != .Windows && !(OS == .Linux && TARGET_ARCH == .x86_64) {
    wait_on_value :: fn(address: ptr[u32], expected: u32) {
        intrinsics.spin_hint()
    }

    wake_one :: fn(address: ptr[u32]) {}

    wake_all :: fn(address: ptr[u32]) {}

    // Threads only start on Windows so far
    os_thread_start :: fn(thread #escaping : ptr[mut Thread]) -> bool {
        return false
    }

    os_thread_join :: fn(thread: ptr[mut Thread]) {}

    // What a hosted program's main starts with
    HOSTED_CONTEXT :: MINIMAL_CONTEXT
}
