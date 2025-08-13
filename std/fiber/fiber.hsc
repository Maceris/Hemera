package fiber

Fiber :: struct {
    frozen_stack : FiberStack,
}

FiberStack :: struct {
    location : rawptr,
    size : uintptr,
}
