package runtime

import intrinsics from "base"

/**
 * A source of random bytes, as context.random holds it.
 *
 * fill may be called by several threads at once, so a generator whose data changes has to be thread-safe.
 */
Random :: struct {
    /** The generator's own state, passed to fill; null for a generator that needs none. */
    data : mut rawptr,
    /**
     * Fill every byte of bytes with random ones. It can't report an error, so a generator that can't give them
     * stops the program rather than leave predictable bytes.
     */
    fill : fn(data: mut rawptr, bytes: mut u8[])
}

/**
 * A random generator with no entropy source, for MINIMAL_CONTEXT. Asking it for bytes traps,
 * since fill can't report an error, and predictable bytes would be worse than stopping.
 */
NO_RANDOM :: Random.{
    data = null,
    fill = no_random_fill,
}

/**
 * Stop the program, as NO_RANDOM's fill, since there are no random bytes to give.
 *
 * @param data Ignored; NO_RANDOM has no state.
 * @param bytes Left as it is: the program traps before anything is written, even when it's empty.
 */
no_random_fill :: fn(data: mut rawptr, bytes: mut u8[]) {
    intrinsics.trap()
}
