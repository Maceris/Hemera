package memory

import intrinsics from "base"
import runtime from "base"

/*
 * An allocator that fails on purpose, for running the error paths that a failed allocation takes (as Linux's failslab
 * does): it passes every request on to the allocator it wraps, except the fail_at'th allocation, counting from 1, which
 * fails with OutOfMemory as if memory had run out. With fail_at 0 it fails nothing and only counts, so a test can learn
 * how many allocations a run makes, then run once failing each:
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
    inner : runtime.Allocator,
    fail_at : u64,
    // Allocations asked for so far, the failed one among them
    allocations : u64,
    // Blocks given out and not yet freed: a run that frees all it took ends where it started
    live : i64,
    // Whether the fail_at'th allocation has come, and failed
    failed : bool,
}

/*
 * A FailingAllocator wrapping inner and failing its fail_at'th allocation, made with inner, since the allocator it is
 * holds it (failing_allocator): null if there's no memory for it. free_failing gives it back.
 */
make_failing :: fn(fail_at: u64, inner := context.allocator) -> ptr[mut FailingAllocator]? {
    made, error :: runtime.new_aligned(FailingAllocator, align_of(FailingAllocator), inner)
    if error != null {
        return null
    }
    made^ = FailingAllocator.{inner = inner, fail_at = fail_at}
    return made
}

free_failing :: fn(failing: ptr[mut FailingAllocator]) {
    runtime.free_aligned(failing, align_of(FailingAllocator), failing.inner)
}

// The allocator a FailingAllocator is, which it must outlive.
failing_allocator :: fn(failing #escaping : ptr[mut FailingAllocator]) -> runtime.Allocator {
    return runtime.Allocator.{failing_function, cast[rawptr](failing)}
}

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
