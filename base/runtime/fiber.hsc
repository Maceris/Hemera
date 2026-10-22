package runtime

import intrinsics from "base"

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

/*
 * A stack segment of at least size bytes, header included, for morestack when the carrier has none
 * to spare (docs/calling_convention.md, Growing the Stack): from the carrier's segment_allocator, and
 * at least STACK_SEGMENT_SIZE. morestack calls it on the thread's native stack, and the function it's
 * growing may have no context to give, so it runs the allocator with MINIMAL_CONTEXT. Null without
 * an allocator or memory, and morestack traps.
 */
allocate_stack_segment #no_context :: fn(size: usize) -> ptr[mut StackSegment]? {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    allocator :: carrier.segment_allocator
    if cast[rawptr](allocator.function) == null {
        return null
    }
    wanted := if size > STACK_SEGMENT_SIZE { size } else { cast[usize](STACK_SEGMENT_SIZE) }
    wanted = (wanted + 15) & ~cast[usize](15)
    block : u8[]
    failed := false
    push_context segments from MINIMAL_CONTEXT {
        made, error :: new_array_aligned(u8, wanted, 16, allocator)
        block = made
        failed = error != null
    }
    if failed {
        return null
    }
    segment :: cast[ptr[mut StackSegment]](block.data)
    segment.size = cast[u32](wanted)
    segment.next_free = null
    return segment
}

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
    // What function is given; an empty any (a null type) when there's none
    data : any,
    // Copied from the context of whoever created the fiber
    context : Context,
    // context's own copy of its extension chain: extension_count nodes
    extension_nodes : rawptr,
    extension_count : u32,
    state : FiberState,
    // Intrusive link for scheduler queues, owned by whichever scheduler holds the fiber
    next : ptr[mut Fiber]?,
    // The fiber's waiter, for park (park.hsc)
    waiter : Waiter,
    // Set by the scheduler that runs the fiber, for wake to queue it again once it's parked
    scheduler : ptr[mut FiberScheduler]?,
}

/*
 * The start of a fiber scheduler's own state, which a fiber points to: what wake calls to queue a
 * parked fiber again, from any thread.
 */
FiberScheduler :: struct {
    wake_function : fn(fiber #escaping : ptr[mut Fiber]),
}

/*
 * Where a suspended fiber continues, see docs/calling_convention.md
 * (Suspending and Resuming a Fiber).
 *
 * While suspended, everything else is on the fiber's own stack, where fiber_suspend pushed it,
 * from saved_sp up, on x86-64 (Windows too, where Hemera's functions use System V's registers):
 *     mxcsr and the x87 control word (16 bytes, with SSE), the innermost frame's base pointer,
 *     the carrier's stack_limit and stack_segment for that segment, r15, r13, r12, rbx, and the
 *     return address into the innermost frame, which is where it continues.
 * The resume loop's state, while the fiber runs, is in the carrier block (resume_frame,
 * resume_return, resume_parent). The carrier register (r14 / x28 / s11) is never saved, so a
 * resumed fiber sees the carrier it's on.
 *
 * The fiber intrinsics and stack walks read these using fixed offsets.
 */
FiberResumeState :: struct {
    // Stack pointer after fiber_suspend pushed everything above
    saved_sp : rawptr,
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
    next_free : ptr[mut StackSegment]?,
}

FiberState :: enum #backed_by(u8) {
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
    data #escaping #crosses_threads : any? = null,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[mut Fiber]?, AllocatorError?) {
    block, error :: new_array_aligned(u8, FIBER_BLOCK_SIZE, 16, allocator, loc)
    if error != null {
        return null, error
    }
    result : ptr[mut Fiber] : cast[ptr[mut Fiber]](block.data)
    result.resume = FiberResumeState.{}
    result.function = function
    nothing : any
    result.data = nothing
    match data {
        case Some(given) => result.data = given
        case None => {}
    }
    result.context = context
    extensions, extensions_error :: copy_extensions(&result.context, allocator, loc)
    if extensions_error != null {
        free_array(block, allocator, loc)
        return null, extensions_error
    }
    result.extension_nodes = cast[rawptr](extensions.data)
    result.extension_count = cast[u32](extensions.count)
    result.state = .NotStarted
    result.next = null
    result.waiter = Waiter.{}
    result.scheduler = null
    return result, null
}

/*
 * The body of every fiber: its function, given its data, with its root context. fiber_entry calls
 * this on the fiber's first stack segment, and switches back to the scheduler with .Finished once
 * it returns (docs/calling_convention.md, Suspending and Resuming a Fiber).
 */
fiber_run #no_context :: fn(fiber: ptr[mut Fiber]) {
    push_context fiber_context from fiber.context {
        fiber.function(fiber.data)
    }
    fiber.state = .Finished
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
    free_array(view_of(cast[ptr[ContextExtension]](fiber.extension_nodes), cast[usize](fiber.extension_count)), allocator, loc)
    // The whole block fiber_create allocated, with its first stack segment: an allocator may tell blocks apart by size
    free_array(view_of(cast[ptr[u8]](fiber), FIBER_BLOCK_SIZE), allocator, loc)
}
