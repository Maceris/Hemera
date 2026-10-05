package intrinsics

import runtime from "base"

mem_copy : fn(dest, source: rawptr, len: usize) : ---
mem_copy_non_overlapping : fn(dest, source: rawptr, len: usize) : ---
mem_zero : fn(target: rawptr, len: usize) : ---

/*
 * Stop the program immediately by executing an illegal instruction (ud2 on x86-64, brk on AArch64),
 * which the OS treats as an abnormal termination. Doesn't depend on the OS, so it works in
 * freestanding builds too. Never returns.
 *
 * At compile time, fails the compilation instead.
 */
trap : fn() : ---

/*
 * Fill addresses with the return addresses of the current call stack, innermost first,
 * starting with the caller of the function that calls this (skipping `skip` more frames).
 * Returns how many were written, at most addresses.count.
 *
 * Walks the base pointer chain, across stack segments, and through the fiber resume loop.
 * Costs nothing until called.
 * Turning the addresses into function names and lines is done separately, from debug info.
 *
 * At compile time the compiler fills this in from its own interpreter's frames.
 */
capture_stack_trace : fn(addresses: mut rawptr[], skip: usize = 0) -> usize : ---

/*
 * Same as capture_stack_trace, for a suspended fiber, starting from its innermost frame.
 * Returns 0 for a fiber that is running, finished, or hasn't started.
 * For debugging stuck fibers.
 */
capture_fiber_stack_trace : fn(fiber: ptr[runtime.Fiber], addresses: mut rawptr[]) -> usize : ---
