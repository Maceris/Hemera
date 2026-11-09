package runtime

import intrinsics from "base"

/**
 * The size in bytes of each additional stack segment, header included, unless a single frame needs more; then the
 * segment is as big as that frame asks.
 */
STACK_SEGMENT_SIZE :: 1024
/**
 * The bytes between stack_limit and the real end of a segment or stack, which a function may use below stack_limit
 * without checking, so small leaf frames and morestack's own call fit before the end.
 */
STACK_GUARD :: 256
/** The usable stack in a fiber's first segment, in bytes, before it needs another segment. */
FIBER_INITIAL_STACK_SIZE :: 1024
/**
 * The size in bytes of the one allocation each fiber is: the Fiber struct (which includes its root context),
 * then its first stack segment, which is the guard plus the usable stack.
 *
 * Fiber is 16-byte aligned, so this stays a multiple of 16. It comes to about 1.4 KiB,
 * under the target of 1.5 GB of runtime overhead per million idle fibers (1536 bytes each),
 * leaving some room for the allocator's own overhead.
 */
FIBER_BLOCK_SIZE :: size_of(Fiber) + STACK_GUARD + FIBER_INITIAL_STACK_SIZE

/**
 * Allocate a stack segment for morestack when the carrier has none to spare.
 *
 * The segment comes from the carrier's segment_allocator (docs/calling_convention.md, Growing the Stack). morestack
 * calls this on the thread's native stack, and the function it's growing may have no context to give, so it runs the
 * allocator with MINIMAL_CONTEXT pushed. The segment is 16-byte aligned, its header's size set and its next_free null.
 *
 * @param size The bytes the segment needs, its StackSegment header included. Anything smaller than
 *     STACK_SEGMENT_SIZE, zero too, gets STACK_SEGMENT_SIZE; the size is then rounded up to a multiple of 16.
 * @return The new segment, owned by the carrier from then on, or null when the carrier has no segment_allocator (its
 *     function is null) or the allocator has no memory; morestack then traps.
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

/**
 * A fiber, and the start of its FIBER_BLOCK_SIZE allocation.
 *
 * Its first stack segment is the rest of the allocation, growing down from the end
 * toward this struct, with stack_limit at (address of this struct) + size_of(Fiber) + STACK_GUARD.
 *
 * The fiber intrinsics read resume using fixed offsets, so keep it first.
 */
Fiber :: struct #align(16) {
    /** Where the fiber continues while it's suspended; meaningless while it runs or before it starts. */
    resume : FiberResumeState,
    /** What the fiber runs, given data, once a scheduler starts it; the fiber is Finished when it returns. */
    function : ThreadFunction,
    /** What function is given; an empty any (a null type) when there's none. */
    data : any,
    /** The fiber's root context, copied from the context of whoever created the fiber. */
    context : Context,
    /**
     * The fiber's own copy of context's extension chain, extension_count nodes in one array from copy_extensions,
     * freed by fiber_destroy; null when the chain was empty.
     */
    extension_nodes : rawptr,
    /** How many nodes extension_nodes holds, 0 when the creator's context had no extensions. */
    extension_count : u32,
    /** Where the fiber is in its life, from NotStarted to Finished. */
    state : FiberState,
    /** Intrusive link for scheduler queues, owned by whichever scheduler holds the fiber; null at the end of one. */
    next : ptr[mut Fiber]?,
    /** The fiber's waiter, for park (park.hsc), which current_waiter gives while the fiber runs. */
    waiter : Waiter,
    /**
     * Set by the scheduler that runs the fiber, for wake to queue it again once it's parked; null until then, and wake
     * then does nothing for a parked fiber.
     */
    scheduler : ptr[mut FiberScheduler]?,
    /**
     * Links in its scheduler's list of every fiber it has that hasn't finished, parked ones too, which a debugger walks
     * to list them; owned by the scheduler, null at either end, and both null for a fiber on no such list.
     */
    all_next : ptr[mut Fiber]?,
    all_previous : ptr[mut Fiber]?,
}

/**
 * The start of a fiber scheduler's own state, which a fiber points to: what wake calls to queue a
 * parked fiber again, from any thread.
 */
FiberScheduler :: struct {
    /**
     * Queue a parked fiber to run again. wake calls it from whichever thread wakes the fiber, so it has to be safe to
     * call from any thread, concurrently with the scheduler.
     */
    wake_function : fn(fiber #escaping : ptr[mut Fiber]),
}

/**
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
    /** The fiber's stack pointer after fiber_suspend pushed everything above. */
    saved_sp : rawptr,
}

/**
 * The header at the low end of an additional stack segment, which grows down toward it.
 *
 * The segment's stack_limit is (address of this) + size_of(StackSegment) + STACK_GUARD.
 * These are similar to how Go used to handle stacks for goroutines, before they
 * switched to stack copying.
 */
StackSegment :: struct #align(16) {
    /** The total size of the segment in bytes, including this header; at least STACK_SEGMENT_SIZE. */
    size : u32,
    /** The link for the carrier's segment cache while the segment is free; null at the cache's end or in use. */
    next_free : ptr[mut StackSegment]?,
}

/** Where a fiber is in its life. */
FiberState :: enum #backed_by(u8) {
    /** Made by fiber_create, and not yet started by a scheduler. */
    NotStarted,
    /** Running on a carrier now. */
    Running,
    /** Switched away from, by a yield or a park, to be resumed later, possibly on another carrier. */
    Suspended,
    /** Its function returned; all that's left is fiber_destroy. */
    Finished,
}

/** Why a fiber switched back to its scheduler. */
FiberExit :: enum {
    /** It suspended, by a yield or a park, and can be resumed. */
    Yielded,
    /** Its function returned, and it can't be resumed. */
    Finished,
}

/**
 * Make a fiber that will run function(data), starting with a copy of the current context.
 *
 * Nothing runs until a scheduler starts it with intrinsics.fiber_start. The fiber, its first stack segment and its
 * copy of the context's extension chain are allocated from allocator, which fiber_destroy has to be given too.
 *
 * @param function What the fiber runs, once started.
 * @param data What function is given, or null for an empty any. It's kept in the fiber until it runs, maybe on
 *     another thread, so it can't point into the caller's stack.
 * @param allocator Where the fiber's memory comes from: one FIBER_BLOCK_SIZE block, 16-byte aligned, and an array of
 *     the context's extensions.
 * @param loc The caller's location, given to the allocator.
 * @return The fiber, NotStarted and with no scheduler yet, owned by the caller until it's given to one; null on an
 *     error.
 * @return The allocator's error when either allocation failed, with nothing left allocated; null on success.
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
        free_array_aligned(block, 16, allocator, loc)
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

/**
 * Run the body of a fiber: its function, given its data, with its root context pushed.
 *
 * fiber_entry calls this on the fiber's first stack segment, and switches back to the scheduler with .Finished once
 * it returns (docs/calling_convention.md, Suspending and Resuming a Fiber).
 *
 * @param fiber The fiber to run, which is set Finished when its function returns.
 */
fiber_run #no_context :: fn(fiber: ptr[mut Fiber]) {
    push_context fiber_context from fiber.context {
        fiber.function(fiber.data)
    }
    fiber.state = .Finished
}

/**
 * Free a fiber that has finished, or never started.
 *
 * Its first stack segment is part of the same allocation, and it doesn't hold any others
 * once it isn't running. A fiber that's suspended can't be freed this way: its stack may still reach other segments.
 *
 * @param fiber The fiber, from fiber_create; it and its copy of the context's extensions are gone after this, so
 *     no scheduler may still hold it.
 * @param allocator The allocator fiber_create was given.
 * @param loc The caller's location, given to the allocator.
 */
fiber_destroy :: fn(
    fiber: ptr[Fiber],
    allocator := context.allocator,
    loc := #caller_location,
) {
    free_array(view_of(cast[ptr[ContextExtension]](fiber.extension_nodes), cast[usize](fiber.extension_count)), allocator, loc)
    // The whole block fiber_create allocated, with its first stack segment: an allocator may tell blocks apart by size
    free_array_aligned(view_of(cast[ptr[u8]](fiber), FIBER_BLOCK_SIZE), 16, allocator, loc)
}
