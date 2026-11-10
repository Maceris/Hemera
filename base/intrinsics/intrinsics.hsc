package intrinsics

import runtime from "base"

/**
 * Copy bytes from one place to another, where the two may overlap, like C's memmove.
 *
 * @param dest Where the bytes go: len bytes there are written.
 * @param source Where they come from: len bytes there are read, as they were before the copy, even where they overlap
 *     dest.
 * @param len How many bytes. 0 copies nothing.
 */
mem_copy : fn(dest: mut rawptr, source: rawptr, len: usize) : ---
/**
 * Copy bytes from one place to another that doesn't overlap it, like C's memcpy, which can be faster than mem_copy.
 *
 * @param dest Where the bytes go: len bytes there are written.
 * @param source Where they come from: len bytes there are read. They mustn't overlap dest's; if they do, what's
 *     written is undefined.
 * @param len How many bytes. 0 copies nothing.
 */
mem_copy_non_overlapping : fn(dest: mut rawptr, source: rawptr, len: usize) : ---
/**
 * Set bytes to zero, like C's memset with 0. The optimizer may leave the write out when nothing reads the bytes after;
 * secure_zero is for when it mustn't.
 *
 * @param target The first byte to zero.
 * @param len How many bytes. 0 writes nothing.
 */
mem_zero : fn(target: mut rawptr, len: usize) : ---
/**
 * Set bytes to zero always, even when nothing reads them after, for wiping secrets (docs/memory.md, Secrets).
 *
 * The write is volatile, so the optimizer can't leave it out as it can mem_zero's.
 *
 * @param target The first byte to zero.
 * @param len How many bytes. 0 writes nothing.
 */
secure_zero : fn(target: mut rawptr, len: usize) : ---
/**
 * Store what a T starts with where target points: zeros, but for its fields' defaults (docs/types.md, Structs).
 *
 * The value is written in place rather than copied there, so a relative pointer in it stays where it's stored. It's
 * what new does when has_defaults(T) is true.
 *
 * @tparam T The type to start, bound from target.
 * @param target Where the T is; all size_of(T) bytes there are written, and whatever was there is lost.
 */
store_defaults : fn[T](target: ptr[mut T]) : ---

/**
 * Give the square root of a float.
 *
 * @tparam F The float type: f16, f32 or f64.
 * @param x The number. Negative numbers have no square root here.
 * @return The float nearest the square root, of the same type; NaN for a negative x or a NaN, and infinity for
 *     infinity.
 */
square_root : fn[F](x: F) -> F : ---

/**
 * Stop the program immediately by executing an illegal instruction (ud2 on x86-64, brk on AArch64),
 * which the OS treats as an abnormal termination. Doesn't depend on the OS, so it works in
 * freestanding builds too.
 *
 * Nothing in the program runs after it, deferred code included. At compile time, fails the compilation instead.
 */
trap #never_returns : fn() : ---

/**
 * Fill addresses with the return addresses of the current call stack, innermost first.
 *
 * Walks the base pointer chain, across stack segments, and through the fiber resume loop.
 * Costs nothing until called.
 * Turning the addresses into function names and lines is done separately, from debug info
 * (runtime.function_at).
 *
 * At compile time the compiler fills this in from its own interpreter's frames.
 *
 * @param addresses Where the return addresses go, from the first element on. Its count is the most that are written;
 *     elements past the result are left as they were.
 * @param skip How many frames to leave out beyond those always skipped: the first address is in the caller of the
 *     function that calls this, and 1 starts one frame further out.
 * @return How many addresses were written, from 0 to addresses.count; fewer than the count when the stack ends first.
 */
capture_stack_trace : fn(addresses: mut rawptr[], skip: usize = 0) -> usize : ---

/**
 * Give where the program's image starts in memory, so an address can be given relative to it, which is
 * the same every run: PE/COFF's __ImageBase, or ELF's __ehdr_start.
 *
 * @return The image's first byte; null where it isn't known, like an ELF image whose headers a linker script left out
 *     of memory, an object format that's neither, or compile-time code.
 */
image_base : fn() -> rawptr : ---

/**
 * Give the start and name of each Hemera function in the program, for naming the frames of a stack trace
 * (runtime.function_at).
 *
 * @return The table, read-only and good for the whole run; empty unless the program was built with debug info
 *     (--debug), and empty in compile-time code.
 */
function_names : fn() -> runtime.FunctionName[] : ---

/**
 * Give the program's import table (docs/compilation.md, Typed Libraries): each export of a typed library it calls,
 * which runtime.bind_libraries binds before main.
 *
 * @return The table, which the program holds for its whole run; empty for a program that calls no typed library, and
 *     in compile-time code.
 */
library_imports : fn() -> runtime.LibraryImports : ---

/**
 * Give the program's coverage counters, for a fuzzer (docs/testing.md, Fuzzing): one for each basic block of the
 * program's code, each bumped every time the block runs, wrapping past 255.
 *
 * @return The counters, which the fuzzer zeroes before an input and reads after; empty unless the program was built
 *     with hemera --fuzz or TargetOptions.coverage, and in compile-time code.
 */
coverage_counters : fn() -> mut u8[] : ---

/**
 * Give the integer constants the program's code compares with for equality, or switches on, for a fuzzer to put in its
 * inputs (docs/testing.md, Fuzzing): magic numbers, tags and the like, which changing bytes at random seldom comes on.
 *
 * @return Each constant once, as a u64, its bits zero-extended, at most 4096 of them, those past 1 only; empty unless
 *     the program was built with hemera --fuzz or TargetOptions.coverage, and in compile-time code.
 */
coverage_constants : fn() -> u64[] : ---

/**
 * Give the stack pointer, for code that sets up its own stack limit, like a kernel's entry before it
 * has a carrier block.
 *
 * @return The stack pointer where it's called. Frames below it may change at any call, so it's for comparing, not for
 *     reading what's there.
 */
stack_pointer : fn() -> rawptr : ---

/**
 * Hint that the caller is spinning, waiting for another thread or CPU to change something:
 * pause on x86-64, yield on AArch64. Nothing on targets without such an instruction.
 *
 * It's only a hint: it doesn't order memory, and the caller still has to read what it waits for atomically.
 */
spin_hint : fn() : ---

/*
 * The compiler's services to compile-time code (docs/compilation.md, Compile-Time Execution), which
 * runtime.COMPILE_TIME_CONTEXT is made of. Only compile-time code can call them; a call in code
 * compiled into a program is an error.
 */
/**
 * Print a log line from compile-time code, with format_string's placeholders filled in from params.
 *
 * @param level How serious it is. ERROR and FATAL fail the build; the others are only printed.
 * @param format_string The text, with placeholders (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where the line is reported as coming from.
 */
compile_time_log : fn(level: runtime.LogLevel, format_string: string, params: any[], location: runtime.SourceCodeLocation) : ---
/**
 * Allocate memory for compile-time code, from the compiler's own heap.
 *
 * @param size How many bytes.
 * @param alignment What the address is a multiple of: a power of two. 0, or one that isn't a power of two, gives 16.
 * @return The memory, uninitialized, which lasts until the compile-time code finishes or compile_time_free gives it
 *     back; null if there's no memory.
 */
compile_time_allocate : fn(size: usize, alignment: usize) -> mut rawptr : ---
/**
 * Give back memory compile_time_allocate gave compile-time code.
 *
 * @param memory What compile_time_allocate returned. Null, or an address it didn't give this run, is ignored.
 */
compile_time_free : fn(memory: rawptr) : ---
/**
 * Fail the build with message at location, and stop the compile-time code there.
 *
 * @param message What went wrong, reported as an assertion's failure.
 * @param location Where the error is reported.
 */
compile_time_fail #never_returns : fn(message: string, location: runtime.SourceCodeLocation) : ---

/**
 * Fill addresses with the return addresses of a suspended fiber's call stack, starting from its innermost frame, as
 * capture_stack_trace does for the running one. For debugging stuck fibers.
 *
 * @param fiber The fiber, which is only read; it should be suspended.
 * @param addresses Where the return addresses go. Its count is the most that are written.
 * @return How many were written, from 0 to addresses.count; 0 for a fiber that is running, finished, or hasn't
 *     started.
 */
capture_fiber_stack_trace : fn(fiber: ptr[runtime.Fiber], addresses: mut rawptr[]) -> usize : ---
