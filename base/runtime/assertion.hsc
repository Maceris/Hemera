package runtime

import compiler from "base"
import intrinsics from "base"

/**
 * Called by assert when an assertion fails, through context.assertion_handler.
 *
 * Handlers end the program, after reporting the failure however they like.
 * Continuing after a failed assertion isn't allowed, so a handler never returns.
 *
 * A handler may be called by several threads or fibers at once, since they inherit it from the
 * context they were created with, so it must be thread-safe. While it runs, the current fiber
 * won't be suspended (it runs in a no-yield region).
 *
 * The handler is given location, where the assertion is in the source, and message, what failed.
 */
AssertionHandler :: alias fn(location: SourceCodeLocation, message: string) #never_returns

/**
 * Check that something is true, and end the program through context.assertion_handler if it isn't.
 *
 * Never returns after a failed assertion. A failed assertion inside a handler (on the same OS thread) traps
 * immediately, instead of calling the handler again.
 *
 * @param assertion What has to be true; when it's false, the program ends.
 * @param message What failed, given to the handler to report; only read when the assertion fails.
 * @param location Where the assertion is, given to the handler; the caller's location by default.
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
    // Only reached if a handler's own assertion failed
    intrinsics.trap()
}

/**
 * Stop the program without reporting anything.
 *
 * The default until something better is installed, like std's default handler.
 *
 * @param location Ignored; nothing is reported.
 * @param message Ignored; nothing is reported.
 */
trap_assertion_handler : AssertionHandler : fn(location: SourceCodeLocation, message: string) #never_returns {
    intrinsics.trap()
}
