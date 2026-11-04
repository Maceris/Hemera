package runtime

import intrinsics from "base"

/**
 * The context compile-time code runs with (docs/compilation.md, Compile-Time Execution).
 *
 * What it logs is printed by the compiler, with errors failing the build; it gets memory that lasts until it
 * finishes; and a failed assertion fails the build. The compiler pushes it before running the code.
 *
 * What it calls only works at compile time, so in a program, where nothing installs it, its log functions do
 * nothing, its allocator has no memory and its assertion handler traps.
 */
COMPILE_TIME_CONTEXT :: Context.{
    allocator = COMPILE_TIME_ALLOCATOR,
    logger = &COMPILE_TIME_LOGGER,
    log_level = .INFO,
    clock = &NO_CLOCK,
    random = &NO_RANDOM,
    assertion_handler = compile_time_assertion_handler,
    user_data = null,
    extensions = null,
}

/**
 * The logger compile-time code logs through: each level's message goes to the compiler, which prints it, an
 * error or fatal one failing the build. In a program, at run time, it logs nothing.
 */
COMPILE_TIME_LOGGER :: Logger.{
    data = null,
    trace = compile_time_trace,
    debug = compile_time_debug,
    info = compile_time_info,
    warn = compile_time_warn,
    error = compile_time_error,
    fatal = compile_time_fatal,
    name = "compile time",
}

/**
 * Log a trace message through the compiler, at compile time; at run time, do nothing.
 *
 * @param format_string The message, with a placeholder for each of params, (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the compiler prints with it; the caller's own by default.
 */
compile_time_trace : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.TRACE, format_string, params, location)
    }
}

/**
 * Log a debug message through the compiler, at compile time; at run time, do nothing.
 *
 * @param format_string The message, with a placeholder for each of params, (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the compiler prints with it; the caller's own by default.
 */
compile_time_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.DEBUG, format_string, params, location)
    }
}

/**
 * Log an information message through the compiler, at compile time; at run time, do nothing.
 *
 * @param format_string The message, with a placeholder for each of params, (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the compiler prints with it; the caller's own by default.
 */
compile_time_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.INFO, format_string, params, location)
    }
}

/**
 * Log a warning through the compiler, at compile time; at run time, do nothing.
 *
 * @param format_string The message, with a placeholder for each of params, (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the compiler prints with it; the caller's own by default.
 */
compile_time_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.WARN, format_string, params, location)
    }
}

/**
 * Log an error through the compiler, which fails the build, at compile time; at run time, do nothing.
 *
 * @param format_string The message, with a placeholder for each of params, (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the compiler reports the error at; the caller's own by default.
 */
compile_time_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.ERROR, format_string, params, location)
    }
}

/**
 * Log a fatal error through the compiler, which fails the build, at compile time; at run time, do nothing.
 *
 * @param format_string The message, with a placeholder for each of params, (docs/format_strings.md).
 * @param params The values for the placeholders, in order.
 * @param location Where it was logged, which the compiler reports the error at; the caller's own by default.
 */
compile_time_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.FATAL, format_string, params, location)
    }
}

/**
 * Fail the build with an assertion's message, at compile time; at run time, where it's never meant to be
 * installed, trap.
 *
 * @param location Where the assertion failed, which the compiler reports the error at.
 * @param message What failed, as the compiler reports it.
 */
compile_time_assertion_handler : AssertionHandler : fn(location: SourceCodeLocation, message: string) #never_returns {
    if #is_compile_time {
        intrinsics.compile_time_fail(message, location)
    }
    intrinsics.trap()
}

/**
 * Allocate, free or resize a block of the compiler's memory, for COMPILE_TIME_ALLOCATOR.
 *
 * What isn't freed before the compile-time code finishes is freed then, so nothing it allocates outlives its run.
 * At run time there's no compiler, so every allocation fails.
 *
 * @param allocator_data Unused; COMPILE_TIME_ALLOCATOR's is null.
 * @param size The block's new size in bytes; 0 frees old_memory.
 * @param alignment The alignment in bytes, a power of two, for a new or resized block.
 * @param old_memory The block to free or resize, from this allocator, or null for a new block. A resized block
 *     moves: the old one is copied, up to the smaller size, then freed, so its address is no longer good.
 * @param old_size old_memory's size in bytes, how much of it is kept when it's resized.
 * @param location Where it was called; unused.
 * @return The block, size bytes; empty when freeing or on an error.
 * @return Null on success, or OutOfMemory when the compiler had no memory to give, or at run time.
 */
compile_time_allocator_function : AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (mut u8[], AllocatorError?) {
    empty : mut u8[]
    // The compiler's memory is only there at compile time
    if !#is_compile_time {
        return empty, AllocatorError.OutOfMemory
    }
    if size == 0 {
        if old_memory != null {
            intrinsics.compile_time_free(old_memory)
        }
        return empty, null
    }
    memory :: intrinsics.compile_time_allocate(size, alignment)
    if memory == null {
        return empty, AllocatorError.OutOfMemory
    }
    if old_memory != null {
        kept := old_size
        if size < kept {
            kept = size
        }
        intrinsics.mem_copy(memory, old_memory, kept)
        intrinsics.compile_time_free(old_memory)
    }
    return view_of(cast[ptr[mut u8]](memory), size), null
}

/**
 * The allocator compile-time code gets memory from: the compiler's, freed when the code finishes if it isn't
 * before (compile_time_allocator_function). At run time it has none.
 */
COMPILE_TIME_ALLOCATOR :: Allocator.{compile_time_allocator_function, null}
