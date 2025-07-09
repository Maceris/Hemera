package runtime

Context :: struct {
    allocator : Allocator,
    logger : Logger,
    log_level : LogLevel,
    stack_trace : ptr[StackTraceNode],
}
