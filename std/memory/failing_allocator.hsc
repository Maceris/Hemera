package memory

import intrinsics from "base"
import runtime from "base"

/**
 * An allocator that fails on purpose, for running the error paths that a failed allocation takes (as Linux's failslab
 * does).
 *
 * It passes every request on to the allocator it wraps, except the fail_at'th allocation, counting from 1, which fails
 * with OutOfMemory as if memory had run out. With fail_at 0 it fails nothing and only counts, so a test can learn how
 * many allocations a run makes, then run once failing each:
 *
 *     failing :: memory.make_failing(n) or_return 1
 *     defer memory.free_failing(failing)
 *     push_context failing_context (allocator = memory.failing_allocator(failing)) {
 *         result = run_the_test()
 *     }
 *     // failing.allocations: how many were asked for; failing.live: blocks given and not freed
 *
 * An allocation is any request for memory: a new block, or a resize to a nonzero size. Freeing never fails. The counts
 * are atomic, so threads can share one.
 */
FailingAllocator :: struct {
    /** The allocator every request but the failing one is passed on to. */
    inner : runtime.Allocator,
    /** Which allocation fails, counting from 1; 0 fails none. Only that one fails, not those after it. */
    fail_at : u64,
    /** Allocations asked for so far, the failed one among them. Changed atomically. */
    allocations : u64,
    /**
     * Blocks given out and not yet freed: a run that frees all it took ends where it started. Signed, since freeing a
     * block from before the wrapper was in place takes it below zero. Changed atomically.
     */
    live : i64,
    /** Whether the fail_at'th allocation has come, and failed. */
    failed : bool,
    /** Where the failed allocation was asked for; meaningful only once failed is true. */
    failed_at : runtime.SourceCodeLocation,
}

/**
 * Make a FailingAllocator wrapping inner and failing its fail_at'th allocation.
 *
 * It's made with inner, since the allocator it is holds it (failing_allocator), and its own allocation isn't counted.
 *
 * @param fail_at Which allocation through it fails, counting from 1; 0 fails none, only counting.
 * @param inner The allocator requests are passed on to, and the FailingAllocator itself comes from. It must outlive it.
 * @return The FailingAllocator, its counts at 0, owned by the caller, who gives it back with free_failing; or null if
 *     inner has no memory for it.
 */
make_failing :: fn(fail_at: u64, inner := context.allocator) -> ptr[mut FailingAllocator]? {
    made, error :: runtime.new_aligned(FailingAllocator, align_of(FailingAllocator), inner)
    if error != null {
        return null
    }
    made^ = FailingAllocator.{inner = inner, fail_at = fail_at}
    return made
}

/**
 * Give a FailingAllocator back to the allocator it wraps.
 *
 * @param failing A FailingAllocator from make_failing, invalid afterwards, as is the allocator made of it. Blocks still
 *     live came from its inner allocator, and are freed with that.
 */
free_failing :: fn(failing: ptr[mut FailingAllocator]) {
    runtime.free_aligned(failing, align_of(FailingAllocator), failing.inner)
}

/**
 * Make the allocator a FailingAllocator is, for context.allocator or anything that takes one.
 *
 * @param failing The FailingAllocator, which must outlive the allocator and everything holding it. Threads can share
 *     it: its counts are atomic.
 * @return An allocator passing requests on to failing's inner allocator, failing the fail_at'th allocation.
 */
failing_allocator :: fn(failing #escaping : ptr[mut FailingAllocator]) -> runtime.Allocator {
    return runtime.Allocator.{failing_function, cast[rawptr](failing)}
}

/**
 * Allocate, free or resize a block, failing the fail_at'th allocation: the function of the allocator failing_allocator
 * makes.
 *
 * An allocation is any request with a nonzero size: a new block, or a resize. Freeing never fails, and only a
 * successful new block or free changes the live count.
 *
 * @param allocator_data The FailingAllocator, as a ptr[mut FailingAllocator].
 * @param size The block's new size in bytes; 0 frees old_memory.
 * @param alignment The block's alignment in bytes, passed on.
 * @param old_memory The block to free or resize, or null to allocate a new one.
 * @param old_size old_memory's size in bytes, as it was allocated.
 * @param location Where the allocation was asked for, recorded in failed_at when it's the one that fails.
 * @return The block, as the inner allocator gives it; empty when the request fails.
 * @return null on success; OutOfMemory for the fail_at'th allocation, leaving any old block as it was; or whatever the
 *     inner allocator returns.
 */
failing_function : runtime.AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (mut u8[], runtime.AllocatorError?) {
    failing :: cast[ptr[mut FailingAllocator]](allocator_data)
    if size > 0 {
        count :: intrinsics.interlocked_exchange_add_u64(&failing.allocations, 1) + 1
        if count == failing.fail_at {
            failing.failed = true
            failing.failed_at = location
            empty : mut u8[]
            return empty, runtime.AllocatorError.OutOfMemory
        }
    }
    result, error :: failing.inner.function(failing.inner.data, size, alignment, old_memory, old_size, location)
    if error == null {
        if old_memory == null && size > 0 {
            _ = intrinsics.interlocked_exchange_add_i64(&failing.live, 1)
        }
        else if old_memory != null && size == 0 {
            _ = intrinsics.interlocked_exchange_add_i64(&failing.live, -1)
        }
    }
    return result, error
}
