/*
 * std/memory's Arena: blocks bumped from chunks, aligned and zeroed; the newest one given back or resized in place;
 * blocks bigger than a chunk; a mark restored to, and a reset keeping the first chunk; a dynamic array and a struct
 * holding pointers into it; new_value's defaults; and running out. Its chunks come from a FailingAllocator, which counts
 * the chunks taken and not given back: one block for the arena itself, and one for each chunk.
 */
package arena_test

import memory from "std"
import runtime from "base"
import testing from "std"

/** A struct with defaults and a pointer, kept in the arena. */
Node :: struct {
    /** Any value; 7 unless given. */
    value : u32 = 7,
    /** The node after this one, or none. */
    next : ptr[Node]?,
}

/** An arena of 4096-byte chunks over a FailingAllocator counting them, for a test. */
Rig :: struct {
    /** What the arena takes its chunks from, and counts them; freed by close. */
    counting : ptr[mut memory.FailingAllocator],
    /** The arena, with no chunk until its first allocation; freed by close. */
    arena : ptr[mut memory.Arena],
    /** The arena as an allocator. */
    allocator : runtime.Allocator,
}

/**
 * Make an arena over a counting allocator, for a test.
 *
 * @param t The test's state, which a failure is recorded in.
 * @return The rig, which the caller gives back with close; Error if either couldn't be made, the failure recorded.
 */
rig :: fn(t: ptr[mut testing.T]) -> Result[Rig, testing.Stopped] {
    counting :: testing.require_some(t, memory.make_failing(0), "the counting allocator is allocated")?
    made :: memory.make_arena(4096, memory.failing_allocator(counting))
    if made is_none {
        memory.free_failing(counting)
        testing.fail(t, "the arena is allocated")
        return .Error(.Failed)
    }
    arena :: made or_return .Error(.Failed)
    return .Ok(Rig.{counting = counting, arena = arena, allocator = memory.arena_allocator(arena)})
}

/**
 * Free a rig's arena, checking it gave back every chunk and itself, then its counting allocator.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param made The rig, not used after.
 */
close :: fn(t: ptr[mut testing.T], made: Rig) {
    memory.free_arena(made.arena)
    testing.expect_eq(t, made.counting.live, 0, "freeing an arena gives back every chunk, and the arena")
    memory.free_failing(made.counting)
}

bumps_aligned_zeroed_blocks_from_one_chunk #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    small, small_error :: runtime.new_array_aligned(u8, 3, 1, r.allocator)
    aligned, aligned_error :: runtime.new_array_aligned(u8, 8, 64, r.allocator)
    testing.require(t, small_error == null, "a 3-byte block fits a 4096-byte chunk")?
    testing.require(t, aligned_error == null, "and an aligned 8-byte one after it")?
    testing.expect_eq(t, r.counting.live, 2, "both come from the first chunk, beside the arena itself")
    testing.require_eq(t, aligned.count, 8, "the block is as long as asked")?
    testing.expect_eq(t, cast[usize](aligned.data) % 64, 0, "the block is aligned as asked")
    if 7 < aligned.count {
        testing.expect_eq(t, aligned[7], 0, "a new block is zeroed")
    }
    testing.expect_le(t, memory.arena_used(r.arena), 3 + 64 + 8, "blocks are packed: no more than alignment between them")
    return .Ok
}

gives_back_the_newest_block #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    _, _ = runtime.new_array_aligned(u8, 3, 1, r.allocator)
    aligned, aligned_error :: runtime.new_array_aligned(u8, 8, 64, r.allocator)
    testing.require(t, aligned_error == null, "an aligned block fits the first chunk")?
    if 7 < aligned.count {
        aligned[7] = 9
    }
    used :: memory.arena_used(r.arena)
    runtime.free_array_aligned(aligned, 64, r.allocator)
    testing.expect_lt(t, memory.arena_used(r.arena), used, "freeing the newest block moves the offset back")
    again, again_error :: runtime.new_array_aligned(u8, 8, 64, r.allocator)
    testing.require(t, again_error == null, "the space given back is there to take")?
    testing.expect_eq(t, again.count, 8, "the block is as long as asked")
    testing.expect(t, again.data == aligned.data, "the next block takes the place given back")
    if 7 < again.count {
        testing.expect_eq(t, again[7], 0, "and comes back zeroed, though 9 was written there")
    }
    return .Ok
}

grows_the_newest_block_in_place #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    numbers : u32[..]
    push_context from_arena (allocator = r.allocator) {
        for i in 0..<100 {
            runtime.array_add(&numbers, cast[u32](i))
        }
    }
    testing.require_eq(t, numbers.count, 100, "every number added is kept")?
    if 99 < numbers.count {
        testing.expect_eq(t, numbers[99], 99, "the last one added is last")
    }
    testing.expect_eq(t, r.counting.live, 2, "growing the newest block stays in the first chunk")
    return .Ok
}

keeps_a_freed_block_that_isnt_the_newest #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    small, small_error :: runtime.new_array_aligned(u8, 3, 1, r.allocator)
    testing.require(t, small_error == null, "a small block fits the first chunk")?
    _, _ = runtime.new_array(u8, 16, r.allocator)
    before :: memory.arena_used(r.arena)
    runtime.free_array_aligned(small, 1, r.allocator)
    testing.expect_eq(t, memory.arena_used(r.arena), before, "only the newest block can be given back, before a reset")
    return .Ok
}

gives_a_block_bigger_than_a_chunk_its_own #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    _, _ = runtime.new_array(u8, 16, r.allocator)
    big, big_error :: runtime.new_array(u8, 10000, r.allocator)
    testing.require(t, big_error == null, "a block bigger than a chunk is still allocated")?
    testing.require_eq(t, big.count, 10000, "as long as asked")?
    if 9999 < big.count {
        testing.expect_eq(t, big[9999], 0, "zeroed to its end")
    }
    testing.expect_eq(t, r.counting.live, 3, "in a chunk of its own, beside the first")
    for i in 0..<50 {
        _ = runtime.new(u64, r.allocator)
    }
    testing.expect_eq(t, r.counting.live, 4, "the arena carries on from the big block's chunk, which is full, in a new one")
    return .Ok
}

restores_a_mark #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    _, _ = runtime.new_array(u8, 16, r.allocator)
    mark :: memory.arena_mark(r.arena)
    before :: memory.arena_used(r.arena)
    _, _ = runtime.new_array(u8, 10000, r.allocator)
    for i in 0..<50 {
        _ = runtime.new(u64, r.allocator)
    }
    memory.arena_restore(r.arena, mark)
    testing.expect_eq(t, r.counting.live, 2, "the chunks taken since the mark are given back")
    testing.expect_eq(t, memory.arena_used(r.arena), before, "the first chunk's offset is back where it was")
    return .Ok
}

keeps_structs_pointing_into_it #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    // Kept where a pointer into the stack couldn't be
    tail :: memory.new_value(Node.{value = 1}, r.allocator)
    head :: memory.new_value(Node.{next = tail}, r.allocator)
    list : Node[..]
    push_context from_arena (allocator = r.allocator) {
        runtime.array_add(&list, head^)
    }
    testing.expect_eq(t, head.value, 7, "new_value keeps the defaults of members it isn't given")
    testing.require_eq(t, list.count, 1, "the copy is added")?
    if 0 < list.count {
        next :: testing.require_some(t, list[0].next, "the copy points at the tail, as the head does")?
        testing.expect_eq(t, next.value, 1, "the tail is still there to point at")
    }
    return .Ok
}

resets_to_its_first_chunk #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    _, _ = runtime.new_array(u8, 16, r.allocator)
    _, _ = runtime.new_array(u8, 5000, r.allocator)
    memory.reset_arena(r.arena)
    testing.expect_eq(t, r.counting.live, 2, "a reset gives back every chunk but the first")
    testing.expect_eq(t, memory.arena_used(r.arena), 0, "and empties that one")
    _, first_error :: runtime.new_array(u8, 16, r.allocator)
    testing.expect(t, first_error == null, "the kept chunk is used again")
    testing.expect_eq(t, r.counting.live, 2, "with no new chunk")
    return .Ok
}

ignores_a_mark_from_before_a_reset #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    _, _ = runtime.new_array(u8, 16, r.allocator)
    _, _ = runtime.new_array(u8, 5000, r.allocator)
    stale :: memory.arena_mark(r.arena)
    memory.reset_arena(r.arena)
    kept :: memory.arena_used(r.arena)
    memory.arena_restore(r.arena, stale)
    testing.expect_eq(t, r.counting.live, 2, "the reset gave back the mark's chunks already: nothing more to give back")
    testing.expect_eq(t, memory.arena_used(r.arena), kept, "and the first chunk's offset isn't moved")
    return .Ok
}

runs_out_when_its_backing_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    r.counting.fail_at = r.counting.allocations + 1
    _, failed :: runtime.new_array(u8, 100000, r.allocator)
    testing.expect(t, failed == runtime.AllocatorError.OutOfMemory, "the chunk this needs can't be taken")
    r.counting.fail_at = 0
    return .Ok
}

refuses_an_alignment_that_isnt_a_power_of_two #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    r :: rig(t)?
    defer close(t, r)
    _, refused :: runtime.new_array_aligned(u8, 4, 3, r.allocator)
    testing.expect(t, refused == runtime.AllocatorError.InvalidArgument, "3 isn't a power of two")
    return .Ok
}
