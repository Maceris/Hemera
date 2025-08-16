package fiber

FiberLocalQueue :: struct {
    //TODO(ches) these need to be atomics
    head : int,
    tail : int,
    buffer : ptr[Fiber][FIBER_LOCAL_QUEUE_SIZE]
}
