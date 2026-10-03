package intrinsics

import runtime from "base"

/*
 * Save the scheduler's registers, set stack_top to the current stack pointer,
 * and call function(data) with fiber_thaw_trampoline as its return address.
 *
 * Returns once the fiber yields or the function returns.
 *
 * The current FiberStackState is kept in a thread-local slot, so the trampoline can find it.
 *
 * Intended for fiber schedulers.
 */
fiber_start : fn(state: ptr[mut FiberStackState], function: fn(any), data: any?) -> FiberExit : ---

/*
 * Saves the scheduler's registers, sets stack_top to the current stack pointer.
 * Then copies the innermost frozen frame (at frozen_low) to just below the stack
 * pointer, moving the stack pointer first so nothing else uses that memory.
 *
 * If more frames are frozen, patches the thawed frame's saved base pointer to
 * its caller's base pointer inside frozen_frames, and its return address to
 * fiber_thaw_trampoline (keeping the real one in patched_return_address).
 *
 * Restores the fiber's registers, and jumps to resume_address.
 *
 * Returns once the fiber yields again or finishes.
 *
 * Intended for fiber schedulers.
 */
fiber_thaw : fn(state: ptr[mut FiberStackState]) -> FiberExit : ---

/*
 * Saves the fiber's registers and resume address, puts patched_return_address
 * back into the outermost thawed frame, and copies [stack pointer, stack_top)
 * to just below frozen_low. Then restores the scheduler's registers, so that its
 * fiber_start/fiber_thaw call returns .Yielded.
 *
 * This can't allocate, so the caller must make sure there are at least
 * (stack_top - stack pointer) free bytes below frozen_low first.
 *
 * Only "returns" when the fiber is thawed again, possibly on another thread.
 *
 * Intended for fiber schedulers.
 */
fiber_freeze : fn(state: ptr[mut FiberStackState]) : ---

/*
 * Never called directly, but needs a name.
 *
 * Its address is written into the return address of thawed frames, so that it
 * runs when that frame returns, with the stack pointer at stack_top.
 *
 * Leaves the return value registers and callee-saved registers alone,
 * thaws the next frozen frame the same way fiber_thaw does, and jumps to the
 * old patched_return_address.
 *
 * If nothing is left to thaw, the fiber is done, and fiber_start/fiber_thaw returns .Finished.
 */
fiber_thaw_trampoline : fn() : ---
