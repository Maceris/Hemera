package fiber

FiberLocalQueue :: struct {
    head : uint,
    tail : uint,
    buffer : ptr[Fiber][FIBER_LOCAL_QUEUE_SIZE]
}
