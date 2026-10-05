package intrinsics

import runtime from "base"

/*
 * The current thread's carrier block, from the carrier register.
 *
 * A fiber can move to another carrier during any call that might yield, so only use
 * the result until then, or inside runtime.no_yield_enter() / runtime.no_yield_exit().
 *
 * At compile time the compiler supplies its own carrier block, with no yield_function.
 */
carrier : fn() -> ptr[mut runtime.CarrierBlock] : ---

/*
 * Start running a fiber that hasn't started yet, on its first stack segment.
 *
 * Saves the scheduler's callee-saved registers and stack pointer in the carrier block,
 * records the shadow stack pointer, makes this fiber the carrier's current fiber,
 * switches the stack pointer to the top of the fiber's first segment, and calls fiber_entry.
 *
 * Returns .Yielded once the fiber suspends, or .Finished once its function returns.
 *
 * Intended for fiber schedulers.
 */
fiber_start : fn(fiber: ptr[mut runtime.Fiber]) -> runtime.FiberExit : ---

/*
 * Resume a suspended fiber, on this carrier.
 *
 * Saves the scheduler's state the same way fiber_start does, then re-enters the fiber's
 * innermost frame with a real call, so that the frame later returns into the resume loop.
 * Each time a re-entered frame returns, the loop re-enters its caller the same way.
 *
 * Returns .Yielded once the fiber suspends again, or .Finished once its function returns.
 *
 * Intended for fiber schedulers.
 */
fiber_resume : fn(fiber: ptr[mut runtime.Fiber]) -> runtime.FiberExit : ---

/*
 * Suspend the current fiber. Called on the fiber's own stack, by the scheduler's
 * yield function (or park), once it has decided to switch.
 *
 * Pushes the fiber's callee-saved registers on its stack, records its innermost frame and
 * where it continues, puts the real return address back into the most recently re-entered
 * frame, drops the fiber's entries from this thread's shadow stack, and switches back to
 * the scheduler, whose fiber_start/fiber_resume call returns .Yielded.
 *
 * Nothing is copied, and nothing is allocated.
 *
 * Only "returns" once the fiber is resumed, possibly on another carrier, so the caller
 * must not use anything it got from carrier() before this.
 *
 * Intended for fiber schedulers.
 */
fiber_suspend : fn(fiber: ptr[mut runtime.Fiber]) : ---

/*
 * Never called directly, but needs a name.
 *
 * The bottom frame of every fiber. Builds a normal frame, calls function(data) with the
 * fiber's root context, and when that returns, marks the fiber .Finished and switches back
 * to the scheduler the same way fiber_suspend does.
 *
 * Its continuation after that call is also where the resume loop ends up if the fiber's
 * function returns after being resumed, so the loop needs no special case for finishing.
 */
fiber_entry : fn() : ---

/*
 * Never called directly, but needs a name.
 *
 * Called by every function's prologue when it doesn't have room left on the current stack
 * segment. Takes a new segment (the carrier's spare, its cache, or a new allocation),
 * copies the function's stack parameters to it, and calls the function's body there.
 * When the body returns, switches back and keeps the segment as the carrier's spare.
 */
morestack : fn() : ---
