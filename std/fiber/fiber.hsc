package fiber

import runtime from "base"

Fiber :: struct {
    function : ThreadFunction,
    data : any?,
    frozen_stack : u8[]?,
    state : FiberState,
}

FiberState :: enum {
    NotStarted,
    Running,
    Suspended,
}