package runtime

import intrinsics from "base"

/**
 * Per-OS-thread execution state, owned by the runtime.
 *
 * Hemera code keeps a pointer to this in the carrier register (r14 on x86-64, x28 on AArch64,
 * s11 on RISC-V), which fiber switches never save or restore. It is loaded from the OS's
 * thread-local storage only when a thread starts, and when foreign code calls back into Hemera.
 *
 * Get it with intrinsics.carrier(). Any call that might yield can move a fiber to another
 * carrier, so a pointer to this is only valid until then, unless inside a no-yield region.
 *
 * Function prologues and the fiber intrinsics read these using fixed offsets,
 * so don't reorder them. stack_limit must stay first.
 */
CarrierBlock :: struct #align(64) {
    /**
     * The lowest address the stack pointer may reach before a function has to call morestack:
     * STACK_GUARD bytes above the real end of the current segment or thread stack.
     */
    stack_limit : rawptr,
    /**
     * The segment the stack pointer is in, null for a fiber's first segment
     * or the thread's own stack.
     */
    stack_segment : ptr[mut StackSegment]?,
    /**
     * The segment most recently left by morestack, kept so a call that keeps
     * crossing a segment boundary doesn't allocate each time; null when there's none.
     */
    spare_segment : ptr[mut StackSegment]?,
    /** The number of foreign calls currently on the stack. Yields and parks decline while this is non-zero. */
    foreign_depth : u32,
    /** The number of no-yield regions currently entered. Yields and parks decline while this is non-zero. */
    no_yield_depth : u32,
    /** The fiber running on this carrier, or null when the thread isn't running one. */
    current_fiber : ptr[mut Fiber]?,
    /**
     * Installed by a fiber scheduler running on this thread, called by fiber_yield
     * when yielding is allowed. Null on plain threads, where fiber_yield does nothing.
     */
    yield_function : fn(carrier: ptr[mut CarrierBlock])?,
    /** Scheduler-defined data for this carrier, installed with yield_function; the runtime doesn't read it. */
    scheduler_data : rawptr,
    /** The scheduler's stack pointer while a fiber runs. Foreign calls run just below it. */
    scheduler_sp : rawptr,
    /** The shadow stack pointer when the current fiber was resumed, 0 without shadow stacks. */
    shadow_stack_base : uintptr,
    /** The stack_limit for this thread's own stack, set when the thread starts. */
    native_stack_limit : rawptr,
    /**
     * The context foreign callbacks run with: the caller's, which each call to a foreign function
     * saves here for the call, and puts back after. Null outside any foreign call.
     */
    foreign_context : ptr[Context]?,
    /** The free stack segments, linked through StackSegment.next_free; null when there are none. */
    segment_cache : ptr[mut StackSegment]?,
    /** How many segments segment_cache holds. */
    segment_cache_count : u32,
    /** A small index identifying this OS thread, for logging and diagnostics; current_thread_index gives it. */
    index : usize,
    /** Set while an assertion handler runs on this carrier, so a failure inside it traps immediately. */
    asserting : bool,
    /** Freestanding programs' own per-carrier data, like a kernel's per-CPU block. Unused by the runtime. */
    program_data : rawptr,
    /**
     * Installed by a fiber scheduler, like yield_function: what park calls to suspend the current
     * fiber until wake(waiter), which then queues it with the fiber's wake_function. Null on plain
     * threads, which block instead.
     */
    park_function : fn(carrier: ptr[mut CarrierBlock], waiter #escaping : ptr[mut Waiter])?,
    /** The thread's own waiter, for park when it isn't running a fiber. */
    thread_waiter : Waiter,
    /**
     * Where a thread's stack pointer was when morestack first took it off its native stack onto a
     * segment, so foreign calls and allocating segments can go back below it. Only meaningful while
     * a thread not running a fiber is on a segment.
     */
    native_sp : rawptr,
    /**
     * Where morestack gets segments when the cache has none big enough: set when the thread starts,
     * from its context's allocator. Without one (no function), it traps instead.
     */
    segment_allocator : Allocator,
    /*
     * The resume loop's state for the fiber running here (docs/calling_convention.md, Resuming), in the three fields
     * below.
     */
    /** The frame the resume loop re-entered last, whose return address slot points into the loop; null if none. */
    resume_frame : rawptr,
    /** The real contents of resume_frame's return address slot, where the frame returns once the loop is done. */
    resume_return : rawptr,
    /** The base pointer of resume_frame's caller, saved before the frame could be popped. */
    resume_parent : rawptr,
    /**
     * The function a call through a C function value is calling, which it leaves here for the shim that moves it onto
     * the thread's own stack (docs/calling_convention.md, Calls to Foreign Code).
     */
    foreign_target : rawptr,
}

/**
 * Fetch the index of the OS thread currently running the caller.
 *
 * @return The carrier's index, a small number identifying the thread for logging and diagnostics. On a fiber, this
 *     could be different after any call that might yield.
 */
current_thread_index :: fn() -> usize {
    return intrinsics.carrier().index
}

/**
 * Enter a no-yield region: until the matching no_yield_exit, fiber_yield and park decline to suspend,
 * so the code stays on the same carrier and pointers from intrinsics.carrier() stay valid.
 *
 * Regions nest; each enter needs its own exit.
 *
 * @example no_yield_enter()
 * defer no_yield_exit()
 */
no_yield_enter :: fn() {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    carrier.no_yield_depth += 1
}

/**
 * Leave the no-yield region the matching no_yield_enter entered; yielding is allowed again once every region is left.
 *
 * It has to match a no_yield_enter on the same carrier: it only takes one from the carrier's count of regions.
 */
no_yield_exit :: fn() {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    carrier.no_yield_depth -= 1
}

/**
 * Signal that now would be a good time to do other work.
 *
 * Only a hint: returns immediately on plain threads, at compile time, with foreign frames
 * on the stack, inside no-yield regions, or when the scheduler has nothing better to run.
 * Otherwise the fiber may be suspended, and resumed later, possibly on another thread.
 */
fiber_yield :: fn() {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    yield_function :: carrier.yield_function or_return void
    if carrier.foreign_depth > 0 || carrier.no_yield_depth > 0 {
        return void
    }
    /*
     * The fiber may be on a different carrier when this returns,
     * so don't use carrier after this.
     */
    yield_function(carrier)
}
