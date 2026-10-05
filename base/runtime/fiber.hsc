package runtime

// Size of each additional stack segment, unless a single frame needs more.
STACK_SEGMENT_SIZE :: 1024
// Bytes between stack_limit and the real end of a segment.
STACK_GUARD :: 256
// Usable stack in a fiber's first segment, before it needs another segment.
FIBER_INITIAL_STACK_SIZE :: 1024
/*
 * Each fiber is one allocation of this size: the Fiber struct (which includes its root context),
 * then its first stack segment, which is the guard plus the usable stack.
 *
 * Fiber is 16-byte aligned, so this stays a multiple of 16. It comes to about 1.4 KiB,
 * under the target of 1.5 GB of runtime overhead per million idle fibers (1536 bytes each),
 * leaving some room for the allocator's own overhead.
 */
FIBER_BLOCK_SIZE :: size_of(Fiber) + STACK_GUARD + FIBER_INITIAL_STACK_SIZE
// Leaf functions with frames up to this size skip the prologue check.
STACK_SMALL :: 128

/*
 * A fiber, and the start of its FIBER_BLOCK_SIZE allocation.
 * Its first stack segment is the rest of the allocation, growing down from the end
 * toward this struct, with stack_limit at (address of this struct) + size_of(Fiber) + STACK_GUARD.
 *
 * The fiber intrinsics read resume using fixed offsets, so keep it first.
 */
Fiber :: struct #align(16) {
    resume : FiberResumeState,
    function : ThreadFunction,
    data : any?,
    // Copied from the context of whoever created the fiber
    context : Context,
    state : FiberState,
    // Intrusive link for scheduler queues, owned by whichever scheduler holds the fiber
    next : ptr[Fiber]?,
}

/*
 * Where a suspended fiber continues, see docs/calling_convention.md
 * (Suspending and Resuming a Fiber).
 *
 * While suspended, the fiber's callee-saved registers are pushed on its own stack, at saved_sp:
 *     x86-64 System V: rbx, r12, r13, r15, mxcsr, x87 control word
 *     x86-64 Windows:  xmm6-xmm15, rbx, rsi, rdi, r12, r13, r15, mxcsr, x87 control word
 *     AArch64:         x19-x27, d8-d15, fpcr
 * The carrier register (r14 / x28) is never saved, so a resumed fiber sees the carrier it's on.
 *
 * The fiber intrinsics read these using fixed offsets, so don't reorder them.
 */
FiberResumeState :: struct {
    // Stack pointer after fiber_suspend pushed the callee-saved registers
    saved_sp : rawptr,
    // Base pointer of the innermost suspended frame
    top_frame : rawptr,
    // Where that frame continues, just after its call to fiber_suspend
    top_continuation : rawptr,
    /*
     * The frame most recently re-entered by the resume loop, whose return address slot
     * points back into the loop. null if there isn't one.
     */
    reentered_frame : rawptr,
    // The original contents of that slot, exactly as they were (still signed, on AArch64)
    reentered_return : rawptr,
    // reentered_frame's caller's base pointer, saved before the frame could be popped
    parent_frame : rawptr,
    // The carrier's stack_segment and stack_limit for the fiber's current segment
    stack_segment : ptr[StackSegment]?,
    stack_limit : rawptr,
}

/*
 * Header at the low end of an additional stack segment, which grows down toward it.
 * The segment's stack_limit is (address of this) + size_of(StackSegment) + STACK_GUARD.
 * These are similar to how Go used to handle stacks for goroutines, before they
 * switched to stack copying.
 */
StackSegment :: struct #align(16) {
    // Total size of the segment in bytes, including this header
    size : u32,
    // Link for the carrier's segment cache, while the segment is free
    next_free : ptr[StackSegment]?,
}

FiberState :: enum {
    NotStarted,
    Running,
    Suspended,
    Finished,
}

FiberExit :: enum {
    Yielded,
    Finished,
}

/*
 * Make a fiber that will run function(data), starting with a copy of the current context.
 * Nothing runs until a scheduler starts it with intrinsics.fiber_start.
 * data is kept in the fiber, so it can't point into the caller's stack.
 */
fiber_create :: fn(
    function: ThreadFunction,
    data #escaping : any? = null,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[Fiber], AllocatorError?) {
    block, error :: new_array_aligned(u8, FIBER_BLOCK_SIZE, 16, allocator, loc)
    if error != null {
        return null, error
    }
    result : ptr[mut Fiber] : cast[ptr[mut Fiber]](block.data)
    result.resume = FiberResumeState.{}
    result.function = function
    result.data = data
    result.context = context
    result.state = .NotStarted
    result.next = null
    return result, null
}

/*
 * Free a fiber that has finished, or never started.
 * Its first stack segment is part of the same allocation, and it doesn't hold any others
 * once it isn't running.
 */
fiber_destroy :: fn(
    fiber: ptr[Fiber],
    allocator := context.allocator,
    loc := #caller_location,
) {
    free(fiber, allocator, loc)
}
