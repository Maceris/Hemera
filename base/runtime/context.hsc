package runtime

/*
 * Passed implicitly to every function call. It follows the logical call chain:
 * threads and fibers get a copy of their creator's context, and it can only be
 * replaced for a scope with push_context, never modified.
 *
 * Nothing about where the code is running (which OS thread, which fiber scheduler)
 * belongs here, since a fiber can move between threads. That lives in CarrierBlock.
 */
Context :: struct {
    allocator : Allocator,
    logger : ptr[Logger],
    log_level : LogLevel,
    clock : ptr[Clock],
    random : ptr[Random],
    assertion_handler : AssertionHandler,
    user_data: rawptr,
}
