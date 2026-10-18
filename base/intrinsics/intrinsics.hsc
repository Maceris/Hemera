package intrinsics

import runtime from "base"

mem_copy : fn(dest, source: rawptr, len: usize) : ---
mem_copy_non_overlapping : fn(dest, source: rawptr, len: usize) : ---
mem_zero : fn(target: rawptr, len: usize) : ---

/*
 * Stop the program immediately by executing an illegal instruction (ud2 on x86-64, brk on AArch64),
 * which the OS treats as an abnormal termination. Doesn't depend on the OS, so it works in
 * freestanding builds too.
 *
 * At compile time, fails the compilation instead.
 */
trap #never_returns : fn() : ---

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
 * Where the program's image starts in memory, so an address can be given relative to it, which is
 * the same every run: PE/COFF's __ImageBase, or ELF's __ehdr_start. Null where it isn't known,
 * like an ELF image whose headers a linker script left out of memory.
 */
image_base : fn() -> rawptr : ---

/*
 * The start and name of each Hemera function in a program built with debug info (--debug), for
 * naming the frames of a stack trace (runtime.function_at). Empty otherwise.
 */
function_names : fn() -> runtime.FunctionName[] : ---

/*
 * The stack pointer, for code that sets up its own stack limit, like a kernel's entry before it
 * has a carrier block. Frames below it may change at any call.
 */
stack_pointer : fn() -> rawptr : ---

/*
 * Hint that the caller is spinning, waiting for another thread or CPU to change something:
 * pause on x86-64, yield on AArch64. Nothing on targets without such an instruction.
 */
spin_hint : fn() : ---

/*
 * The compiler's services to compile-time code (docs/compilation.md, Compile-Time Execution), which
 * runtime.COMPILE_TIME_CONTEXT is made of. Only compile-time code can call them.
 */
// Print a log line, with format_string's placeholders filled in from params. ERROR and FATAL fail the build.
compile_time_log : fn(level: runtime.LogLevel, format_string: string, params: any[], location: runtime.SourceCodeLocation) : ---
// size bytes, aligned to alignment, that last until the compile-time code finishes; null if there's no memory.
compile_time_allocate : fn(size: usize, alignment: usize) -> rawptr : ---
compile_time_free : fn(memory: rawptr) : ---
// Fail the build with message at location, and stop the compile-time code there.
compile_time_fail #never_returns : fn(message: string, location: runtime.SourceCodeLocation) : ---

/*
 * Same as capture_stack_trace, for a suspended fiber, starting from its innermost frame.
 * Returns 0 for a fiber that is running, finished, or hasn't started.
 * For debugging stuck fibers.
 */
capture_fiber_stack_trace : fn(fiber: ptr[runtime.Fiber], addresses: mut rawptr[]) -> usize : ---
