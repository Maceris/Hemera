package aarch64

/*
 * System instructions for AArch64, for the runtime and for kernels and other freestanding code.
 *
 * Only exists when TARGET_ARCH == .arm64, where intrinsics' platform.hsc imports it, so use it from
 * architecture-specific code only.
 */

// System calls, from user mode

/*
 * A system call with Linux's AArch64 convention: svc #0, the number in x8, up to six arguments in x0 to
 * x5, and the result in x0, where -4095 to -1 are errors (-errno). It doesn't use the stack, so it works on
 * a fiber's small one.
 */
syscall : fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 : ---

/*
 * Linux's clone for a new thread, which starts on stack (its top) by calling entry(argument), with the C
 * convention; entry must end the thread with the exit system call rather than return. The kernel stores
 * the new thread's ID through parent_tid before this returns, and clears it through child_tid, waking futex
 * waiters there, once the thread has exited (with CLONE_PARENT_SETTID and CLONE_CHILD_CLEARTID in flags).
 * Returns the new thread's ID, or -errno.
 */
clone_thread : fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
    argument: rawptr) -> i64 : ---
