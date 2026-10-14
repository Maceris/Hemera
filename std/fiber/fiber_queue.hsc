package fiber

import runtime from "base"

FiberLocalQueue :: struct {
    head : uint,
    tail : uint,
    buffer : ptr[mut Fiber][FIBER_LOCAL_QUEUE_SIZE]
}
