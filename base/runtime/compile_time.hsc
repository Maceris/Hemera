package runtime

import intrinsics from "base"

/*
 * The context compile-time code runs with (docs/compilation.md, Compile-Time Execution): what it logs is
 * printed by the compiler, with errors failing the build; it gets memory that lasts until it finishes; and a
 * failed assertion fails the build. The compiler pushes it before running the code.
 *
 * What it calls only works at compile time, so in a program, where nothing installs it, its log
 * functions do nothing, its allocator has no memory and its assertion handler traps.
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
    if #is_compile_time {
        intrinsics.compile_time_log(.TRACE, format_string, params, location)
    }
}

compile_time_debug : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.DEBUG, format_string, params, location)
    }
}

compile_time_info : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.INFO, format_string, params, location)
    }
}

compile_time_warn : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.WARN, format_string, params, location)
    }
}

compile_time_error : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.ERROR, format_string, params, location)
    }
}

compile_time_fatal : LogFunction : fn(format_string: string, params: any..., location := #caller_location) {
    if #is_compile_time {
        intrinsics.compile_time_log(.FATAL, format_string, params, location)
    }
}

compile_time_assertion_handler : AssertionHandler : fn(location: SourceCodeLocation, message: string) #never_returns {
    if #is_compile_time {
        intrinsics.compile_time_fail(message, location)
    }
    intrinsics.trap()
}

// Memory from the compiler, freed when the compile-time code finishes if it isn't before.
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

COMPILE_TIME_ALLOCATOR :: Allocator.{compile_time_allocator_function, null}
