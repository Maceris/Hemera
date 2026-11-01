/*
 * std/memory's Arena: blocks bumped from chunks, aligned and zeroed; the newest one given back or resized in place;
 * blocks bigger than a chunk; a mark restored to, and a reset keeping the first chunk; a dynamic array and a struct
 * holding pointers into it; new_value's defaults; and running out. Its chunks come from a FailingAllocator, which counts
 * the chunks taken and not given back. main returns 42 if each worked, or the number of the first check that didn't.
 */
package arena_test

import memory from "std"
import runtime from "base"

Node :: struct {
    value : u32 = 7,
    next : ptr[Node]?,
}

main :: fn() -> int {
    counting :: memory.make_failing(0) or_return 1
    defer memory.free_failing(counting)
    arena :: memory.make_arena(4096, memory.failing_allocator(counting)) or_return 2
    allocator :: memory.arena_allocator(arena)

    // Aligned and zeroed, packed one after another in the first chunk
    small, small_error :: runtime.new_array_aligned(u8, 3, 1, allocator)
    aligned, aligned_error :: runtime.new_array_aligned(u8, 8, 64, allocator)
    if small_error != null || aligned_error != null || counting.live != 2 {
        return 3
    }
    if aligned.count != 8 || cast[usize](aligned.data) % 64 != 0 || aligned[7] != 0 || memory.arena_used(arena) > 3 + 64 + 8 {
        return 4
    }
    aligned[7] = 9

    // The newest block is given back, and comes back zeroed
    used :: memory.arena_used(arena)
    runtime.free_array_aligned(aligned, 64, allocator)
    if memory.arena_used(arena) >= used {
        return 5
    }
    again, again_error :: runtime.new_array_aligned(u8, 8, 64, allocator)
    if again_error != null || again.count != 8 || again.data != aligned.data || again[7] != 0 {
        return 6
    }

    // A dynamic array growing from it: the newest block grows where it is
    numbers : u32[..]
    push_context from_arena (allocator = allocator) {
        for i in 0..<100 {
            runtime.array_add(&numbers, cast[u32](i))
        }
    }
    if numbers.count != 100 || numbers[99] != 99 || counting.live != 2 {
        return 7
    }

    // What's freed that isn't the newest stays until a reset
    mark :: memory.arena_mark(arena)
    before :: memory.arena_used(arena)
    runtime.free_array_aligned(small, 1, allocator)
    if memory.arena_used(arena) != before {
        return 8
    }

    // A block bigger than a chunk gets one of its own, and the arena carries on from it
    big, big_error :: runtime.new_array(u8, 10000, allocator)
    if big_error != null || big.count != 10000 || big[9999] != 0 || counting.live != 3 {
        return 9
    }
    for i in 0..<50 {
        _ = runtime.new(u64, allocator)
    }
    if counting.live != 4 {
        return 10
    }

    // Back to the mark: the chunks taken since are given back
    memory.arena_restore(arena, mark)
    if counting.live != 2 || memory.arena_used(arena) != before {
        return 11
    }

    // Structs holding pointers into it, kept where a pointer into the stack couldn't be
    tail :: memory.new_value(Node.{value = 1}, allocator)
    head :: memory.new_value(Node.{next = tail}, allocator)
    list : Node[..]
    push_context from_arena (allocator = allocator) {
        runtime.array_add(&list, head^)
    }
    if head.value != 7 || list.count != 1 || (list[0].next or_return 12).value != 1 {
        return 13
    }

    // A reset keeps only the first chunk
    _, _ = runtime.new_array(u8, 5000, allocator)
    memory.reset_arena(arena)
    if counting.live != 2 || memory.arena_used(arena) != 0 {
        return 14
    }
    first, first_error :: runtime.new_array(u8, 16, allocator)
    if first_error != null || counting.live != 2 {
        return 15
    }

    // A mark from before the reset, whose chunks it gave back: nothing more to give back
    _, _ = runtime.new_array(u8, 5000, allocator)
    stale :: memory.arena_mark(arena)
    memory.reset_arena(arena)
    kept :: memory.arena_used(arena)
    memory.arena_restore(arena, stale)
    if counting.live != 2 || memory.arena_used(arena) != kept {
        return 19
    }

    // Out of memory when the backing allocator is
    counting.fail_at = counting.allocations + 1
    _, failed :: runtime.new_array(u8, 100000, allocator)
    if failed != runtime.AllocatorError.OutOfMemory {
        return 16
    }
    counting.fail_at = 0

    // An alignment that isn't a power of two
    _, refused :: runtime.new_array_aligned(u8, 4, 3, allocator)
    if refused != runtime.AllocatorError.InvalidArgument {
        return 17
    }

    // Freeing gives back every chunk and the arena
    memory.free_arena(arena)
    if counting.live != 0 {
        return 18
    }
    return 42
}
