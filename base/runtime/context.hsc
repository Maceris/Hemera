package runtime

Context :: struct {
    allocator : Allocator,
    logger : Logger,
    log_level : LogLevel,
    stack_trace : ptr[StackTraceNode],
    thread_index : ThreadIndex,
    /* 
     * Specifies the function to call for yielding from a fiber.
     * Only has a value when running on a fiber.
     */
    fiber_yield_function : fn()?,
    /*
     * When running a fiber, stores the currently executing fiber functions
     * stack frame, so that we know where to drop the stack back to when
     * yielding.
     */
    fiber_base_pointer : rawptr,
}
