package fiber

FiberLocalQueue :: struct {
    head : uint,
    tail : uint,
    buffer : ptr[mut Fiber][FIBER_LOCAL_QUEUE_SIZE]
}
