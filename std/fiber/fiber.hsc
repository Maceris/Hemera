package fiber

Fiber :: struct {
    frozen_stack : ptr[FiberStack]?,
    state : FiberState,
}

FiberStack :: struct {
    location : rawptr,
    size : uintptr,
}

FiberState :: enum {
    NotStarted,
    Running,
    Suspended,
}