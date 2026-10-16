package runtime

import intrinsics from "base"

/*
 * The context compile-time code runs with (docs/compilation.md, Compile-Time Execution): what it logs is
 * printed by the compiler, with errors failing the build; it gets memory that lasts until it finishes; and a
 * failed assertion fails the build. The compiler pushes it before running the code.
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

compile_time_trace : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    intrinsics.compile_time_log(.TRACE, format_string, params, location)
}

compile_time_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    intrinsics.compile_time_log(.DEBUG, format_string, params, location)
}

compile_time_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    intrinsics.compile_time_log(.INFO, format_string, params, location)
}

compile_time_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    intrinsics.compile_time_log(.WARN, format_string, params, location)
}

compile_time_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    intrinsics.compile_time_log(.ERROR, format_string, params, location)
}

compile_time_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    intrinsics.compile_time_log(.FATAL, format_string, params, location)
}

compile_time_assertion_handler : AssertionHandler : fn(location: SourceCodeLocation, message: string) #never_returns {
    intrinsics.compile_time_fail(message, location)
}

// Memory from the compiler, freed when the compile-time code finishes if it isn't before.
compile_time_allocator_function : AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (u8[], AllocatorError?) {
    empty : u8[]
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

COMPILE_TIME_ALLOCATOR :: Allocator.{compile_time_allocator_function, null}
