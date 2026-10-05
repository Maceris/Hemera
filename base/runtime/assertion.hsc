package runtime

import compiler from "base"
import intrinsics from "base"

/*
 * Called by assert when an assertion fails, through context.assertion_handler.
 *
 * Handlers are expected to end the program, after reporting the failure however they like.
 * Continuing after a failed assertion isn't allowed: if a handler returns, assert traps.
 *
 * A handler may be called by several threads or fibers at once, since they inherit it from the
 * context they were created with, so it must be thread-safe. While it runs, the current fiber
 * won't be suspended (it runs in a no-yield region).
 */
AssertionHandler :: alias fn(location: SourceCodeLocation, message: string) -> void

/*
 * If assertion is false, calls context.assertion_handler, which should end the program.
 * Never returns after a failed assertion.
 *
 * A failed assertion inside a handler (on the same OS thread) traps immediately,
 * instead of calling the handler again.
 */
assert :: fn(assertion: bool, message: string, location := #caller_location) {
    if assertion {
        return void
    }
    /*
     * No other fiber runs on this carrier until we're done, so the carrier's
     * asserting flag only means this call chain is already in a handler.
     * We are killing the program so the lack of no_yield_exit() doesn't matter.
     */
    no_yield_enter()
    carrier :: intrinsics.carrier()
    if !carrier.asserting {
        carrier.asserting = true
        context.assertion_handler(location, message)
    }
    // Only reached if the handler returned, or a handler's own assertion failed
    intrinsics.trap()
}

/*
 * Stops the program without reporting anything.
 * The default until something better is installed, like std's default handler.
 */
trap_assertion_handler : AssertionHandler : fn(location: SourceCodeLocation, message: string) {
    intrinsics.trap()
}
