package runtime

import intrinsics from "base"

/*
 * Per-OS-thread execution state, owned by the runtime.
 *
 * Hemera code keeps a pointer to this in the carrier register (r14 on x86-64, x28 on AArch64),
 * which fiber switches never save or restore. It is loaded from the OS's thread-local storage
 * only when a thread starts, and when foreign code calls back into Hemera.
 *
 * Get it with intrinsics.carrier(). Any call that might yield can move a fiber to another
 * carrier, so a pointer to this is only valid until then, unless inside a no-yield region.
 *
 * Function prologues and the fiber intrinsics read these using fixed offsets,
 * so don't reorder them. stack_limit must stay first.
 */
CarrierBlock :: struct #align(64) {
    /*
     * Lowest address the stack pointer may reach before a function has to call morestack.
     * STACK_GUARD bytes above the real end of the current segment or thread stack.
     */
    stack_limit : rawptr,
    /*
     * The segment the stack pointer is in, null for a fiber's first segment
     * or the thread's own stack.
     */
    stack_segment : ptr[StackSegment]?,
    /*
     * The segment most recently left by morestack, kept so a call that keeps
     * crossing a segment boundary doesn't allocate each time.
     */
    spare_segment : ptr[StackSegment]?,
    // Number of foreign calls currently on the stack. Yields decline while this is non-zero.
    foreign_depth : u32,
    // Number of no-yield regions currently entered. Yields decline while this is non-zero.
    no_yield_depth : u32,
    // The fiber running on this carrier, if any.
    current_fiber : ptr[Fiber]?,
    /*
     * Installed by a fiber scheduler running on this thread, called by fiber_yield
     * when yielding is allowed. Null on plain threads.
     */
    yield_function : fn(carrier: ptr[mut CarrierBlock])?,
    // Scheduler-defined data for this carrier, installed by yield_function.
    scheduler_data : rawptr,
    // The scheduler's stack pointer while a fiber runs. Foreign calls run just below it.
    scheduler_sp : rawptr,
    // The shadow stack pointer when the current fiber was resumed, 0 without shadow stacks.
    shadow_stack_base : uintptr,
    // stack_limit for this thread's own stack.
    native_stack_limit : rawptr,
    // The context foreign callbacks run with, saved by the most recent foreign call.
    foreign_context : ptr[Context]?,
    // Free stack segments, linked through StackSegment.next_free.
    segment_cache : ptr[StackSegment]?,
    segment_cache_count : u32,
    // Small index identifying this OS thread, for logging and diagnostics.
    index : usize,
    // Set while an assertion handler runs on this carrier, so a failure inside it traps immediately.
    asserting : bool,
}

/*
 * Index of the OS thread currently running the caller.
 * On a fiber, this could be different after any call that might yield.
 */
current_thread_index :: fn() -> usize {
    return intrinsics.carrier().index
}

/*
 * Enter a no-yield region: until the matching no_yield_exit, fiber_yield declines,
 * so the code stays on the same carrier and pointers from intrinsics.carrier() stay valid.
 *
 * no_yield_enter()
 * defer no_yield_exit()
 */
no_yield_enter :: fn() {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    carrier.no_yield_depth += 1
}

no_yield_exit :: fn() {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    carrier.no_yield_depth -= 1
}

/*
 * Signals that now would be a good time to do other work.
 *
 * Only a hint: returns immediately on plain threads, at compile time, with foreign frames
 * on the stack, inside no-yield regions, or when the scheduler has nothing better to run.
 * Otherwise the fiber may be suspended, and resumed later, possibly on another thread.
 */
fiber_yield :: fn() {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    yield_function :: carrier.yield_function or_return
    if carrier.foreign_depth > 0 || carrier.no_yield_depth > 0 {
        return void
    }
    /*
     * The fiber may be on a different carrier when this returns,
     * so don't use carrier after this.
     */
    yield_function(carrier)
}
