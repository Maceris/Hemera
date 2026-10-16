package compile_time_assertion

import runtime from "base"

// A failed assertion in compile-time code fails the build, once
size :: fn() -> int {
    runtime.assert(false, "no size today")
    return 16
}

SIZE :: size()

buffer_of :: fn() -> int {
    buffer : u8[SIZE]
    return 0
}
