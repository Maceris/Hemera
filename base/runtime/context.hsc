package runtime

Context :: struct {
    allocator : Allocator,
    logger : Logger,
    log_level : LogLevel,
    stack_trace : ptr[StackTraceNode],
    thread_index : ThreadIndex,
    /* 
     * Indicates that the current thread is part of a fiber runtime.
     * Basically only used to determine whether yield() does anything.
     */
    is_running_on_a_fiber : bool,
    /*
     * When running a fiber, stores the currently executing fiber functions
     * stack frame, so that we know where to drop the stack back to when
     * yielding.
     */
    fiber_base_pointer : rawptr,
}
