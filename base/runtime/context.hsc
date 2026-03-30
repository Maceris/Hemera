package runtime

Context :: struct {
    allocator : Allocator,
    logger : ptr[Logger],
    log_level : LogLevel,
    stack_trace : ptr[StackTraceNode],
    thread_index : usize,
    is_running_on_a_fiber : bool,
    /* 
     * Specifies the function to call for yielding from a fiber.
     * Only has a value when running on a fiber.
     */
    fiber_yield_function : fn()?,
    fiber_data: rawptr,
}
