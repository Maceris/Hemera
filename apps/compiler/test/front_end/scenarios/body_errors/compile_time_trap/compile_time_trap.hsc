package compile_time_trap

import intrinsics from "base"

// A trap in compile-time code fails the build instead of the compiler
size :: fn() -> int {
    intrinsics.trap()
}

SIZE :: size()

buffer_of :: fn() -> int {
    buffer : u8[SIZE]
    return 0
}
