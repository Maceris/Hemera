package fiber

import runtime from "base"

Fiber :: struct {
    function : ThreadFunction,
    data : any?,
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