package riscv64

/*
 * Instructions for 64-bit RISC-V, for the runtime and for kernels and other freestanding code.
 *
 * Each function is one instruction, named after it, or a short sequence the runtime needs whole. Only exists when
 * TARGET_ARCH == .riscv64, where intrinsics' platform.hsc imports it, so use it from architecture-specific code only.
 */

// Linux

/**
 * Make a Linux system call: ecall, the number in a7, up to six arguments in a0 to a5, the result in a0. Every other
 * register is kept.
 *
 * @param number The system call's number, in a7.
 * @param a The first argument, in a0; 0 when the call takes fewer.
 * @param b The second argument, in a1.
 * @param c The third argument, in a2.
 * @param d The fourth argument, in a3.
 * @param e The fifth argument, in a4.
 * @param f The sixth argument, in a5.
 * @return a0 after the call: -4095 to -1, as an i64, are errors (-errno), and anything else is the call's result.
 */
syscall : fn(number : u64, a : u64 = 0, b : u64 = 0, c : u64 = 0, d : u64 = 0, e : u64 = 0, f : u64 = 0) -> u64 : ---

/**
 * Start a thread with Linux's clone, which starts on stack by calling entry(argument), with the C convention.
 *
 * @param flags clone's flags. With CLONE_PARENT_SETTID and CLONE_CHILD_CLEARTID, the kernel stores the new thread's ID
 *     through parent_tid, and clears it through child_tid once the thread has exited.
 * @param stack The top of the new thread's stack, 16-byte aligned, which the caller allocated and keeps until the
 *     thread has exited.
 * @param parent_tid Where the kernel stores the new thread's ID before this returns.
 * @param child_tid Where the kernel writes 0 once the thread has exited, waking futex waiters there, so a joiner waits
 *     on it.
 * @param entry The function the thread runs, with the C convention; it must end the thread with the exit system call
 *     rather than return.
 * @param argument What entry is given as its one argument.
 * @return The new thread's ID, or -errno if clone failed, in which case no thread started.
 */
clone_thread : fn(
    flags : u64,
    stack : rawptr,
    parent_tid : ptr[mut u32],
    child_tid : ptr[mut u32],
    entry : rawptr,
    argument : rawptr
) -> i64 : ---
