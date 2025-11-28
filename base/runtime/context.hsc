package runtime

Context :: struct {
    allocator : Allocator,
    logger : ptr[Logger],
    log_level : LogLevel,
    stack_trace : ptr[StackTraceNode],
    thread_index : usize,
    /* 
     * Specifies the function to call for yielding from a fiber.
     * Only has a value when running on a fiber.
     */
    fiber_yield_function : fn()?,
    //TODO(ches) should fiber_base_pointer go in the FiberSchedulerLocalData?
    /*
     * When running a fiber, stores the currently executing fiber functions
     * stack frame, so that we know where to drop the stack back to when
     * yielding.
     */
    fiber_base_pointer : rawptr,
}
