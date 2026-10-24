package runtime

import intrinsics from "base"

Random :: struct {
    data : mut rawptr,
    fill : fn(data: mut rawptr, bytes: mut u8[])
}

/*
 * A random generator with no entropy source, for MINIMAL_CONTEXT. Asking it for bytes traps,
 * since fill can't report an error, and predictable bytes would be worse than stopping.
 */
NO_RANDOM :: Random.{
    data = null,
    fill = no_random_fill,
}

no_random_fill :: fn(data: mut rawptr, bytes: mut u8[]) {
    intrinsics.trap()
}
