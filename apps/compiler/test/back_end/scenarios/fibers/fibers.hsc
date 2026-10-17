/*
 * Fibers in a hosted program, run by std/fiber's scheduler: main returns 42 if everything worked,
 * or the number of the first check that failed. Built with stack_check = .Morestack, so a fiber
 * that recurses deeply grows onto segments.
 *
 * Nothing here calls foreign code, which fibers can't do yet: memory comes from an arena in main's
 * frame.
 */
package fibers

import intrinsics from "base"
import runtime from "base"
import fiber from "std"

ARENA_SIZE :: 131072
SEGMENT_SIZE :: 4096
SEGMENT_COUNT :: 8

Arena :: struct {
    bytes : u8[ARENA_SIZE],
    used : usize,
    // Allocations not freed yet
    live : usize,
}

// Memory from the arena, never reused: freeing only counts.
arena_function : runtime.AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (u8[], runtime.AllocatorError?) {
    arena :: cast[ptr[mut Arena]](allocator_data)
    empty : u8[]
    if size == 0 {
        if old_memory != null {
            arena.live -= 1
        }
        return empty, null
    }
    base :: cast[usize](&arena.bytes)
    start :: (base + arena.used + alignment - 1) / alignment * alignment - base
    if start + size > ARENA_SIZE {
        return empty, runtime.AllocatorError.OutOfMemory
    }
    arena.used = start + size
    arena.live += 1
    return view_of(cast[ptr[mut u8]](cast[rawptr](base + start)), size), null
}

// What the fibers record, found through context.user_data.
Turns :: struct {
    marks : u8[16],
    count : usize,
    // Stack traces at the bottom of a's calls, before yielding and once resumed
    before : rawptr[32],
    before_count : usize,
    after : rawptr[32],
    after_count : usize,
    deep_sum : u64,
    // Whether the deepest call was on a segment morestack gave it
    deep_on_segment : bool,
}

// What the fibers write, in the order taking turns gives: b keeps running once it's alone.
EXPECTED_MARKS :: "abABC"

mark :: fn(turns: ptr[mut Turns], letter: char) {
    if turns.count < 16 {
        turns.marks[turns.count] = cast[u8](letter)
        turns.count += 1
    }
}

// Down a chain of calls, yielding at the bottom: each frame's local and result have to survive it.
descend :: fn(turns: ptr[mut Turns], depth: u64) -> u64 {
    here : u64 = 0
    intrinsics.volatile_store_u64(&here, depth * 10 + 1)
    if depth == 0 {
        mark(turns, 'a')
        turns.before_count = intrinsics.capture_stack_trace(turns.before)
        runtime.fiber_yield()
        turns.after_count = intrinsics.capture_stack_trace(turns.after)
        return intrinsics.volatile_load_u64(&here)
    }
    below :: descend(turns, depth - 1)
    return below + intrinsics.volatile_load_u64(&here)
}

worker_a : runtime.ThreadFunction : fn(data #escaping : any) {
    turns :: cast[ptr[mut Turns]](context.user_data)
    // 31 + (21 + (11 + 1))
    mark(turns, if descend(turns, 3) == 64 { 'A' } else { 'x' })
}

worker_b : runtime.ThreadFunction : fn(data #escaping : any) {
    turns :: cast[ptr[mut Turns]](context.user_data)
    mark(turns, 'b')
    runtime.fiber_yield()
    mark(turns, 'B')
    // Alone now, so this keeps running
    runtime.fiber_yield()
    mark(turns, 'C')
}

// About 64 bytes of stack a call, so 1 to 256 is about 16 KiB: past the fiber's first segment.
climb :: fn(depth: u64) -> u64 {
    // Read back after the call, so it isn't turned into a loop
    padding : u64[4]
    intrinsics.volatile_store_u64(&padding[0], depth)
    if depth == 256 {
        turns :: cast[ptr[mut Turns]](context.user_data)
        turns.deep_on_segment = intrinsics.carrier().stack_segment != null
        return depth
    }
    below :: climb(depth + 1)
    return below + intrinsics.volatile_load_u64(&padding[0])
}

worker_deep : runtime.ThreadFunction : fn(data #escaping : any) {
    turns :: cast[ptr[mut Turns]](context.user_data)
    turns.deep_sum = climb(1)
}

// Segments for morestack, in the carrier's cache before the fibers run.
cache_segments :: fn(carrier: ptr[mut runtime.CarrierBlock]) -> bool {
    for i in 0..<SEGMENT_COUNT {
        made, error :: runtime.new_array_aligned(u8, SEGMENT_SIZE, 16)
        if error != null {
            return false
        }
        segment :: cast[ptr[mut runtime.StackSegment]](made.data)
        segment.size = cast[u32](SEGMENT_SIZE)
        segment.next_free = carrier.segment_cache
        carrier.segment_cache = segment
        carrier.segment_cache_count += 1
    }
    return true
}

segments_cached :: fn(carrier: ptr[runtime.CarrierBlock]) -> usize {
    count : usize = 0
    walk := carrier.segment_cache
    loop {
        segment :: walk or_break
        count += 1
        walk = segment.next_free
    }
    match carrier.spare_segment {
        case Some(spare) => count += 1
        case None => {}
    }
    return count
}

same_trace :: fn(turns: ptr[Turns]) -> bool {
    if turns.before_count == 0 || turns.before_count != turns.after_count {
        return false
    }
    for i in 0..<turns.before_count {
        if i < 32 && turns.before[i] != turns.after[i] {
            return false
        }
    }
    return true
}

main :: fn() -> int {
    arena : Arena
    arena.used = 0
    arena.live = 0
    /*
     * The arena outlives everything that uses it, but an allocator can't hold a pointer into the
     * stack (docs/memory.md, Unrestricted Structs), so its address goes through an integer
     */
    arena_address :: cast[rawptr](cast[usize](&arena))
    push_context with_arena (allocator = runtime.Allocator.{arena_function, arena_address}) {
        carrier :: intrinsics.carrier()
        if !cache_segments(carrier) {
            return 1
        }
        turns :: runtime.new(Turns)
        turns.count = 0
        turns.deep_sum = 0
        turns.deep_on_segment = false
        scheduler :: fiber.create_fiber_scheduler()
        push_context with_turns (user_data = cast[rawptr](turns)) {
            _, error_a :: fiber.spawn(scheduler, worker_a)
            _, error_b :: fiber.spawn(scheduler, worker_b)
            _, error_deep :: fiber.spawn(scheduler, worker_deep)
            if error_a != null || error_b != null || error_deep != null {
                return 2
            }
        }
        live_before :: arena.live
        fiber.run_fibers(scheduler)
        // The deep fiber runs between a's and b's turns: "ab", then its own, then "AB" and "C"
        if string_of(&turns.marks[0], turns.count) != EXPECTED_MARKS {
            return 3
        }
        if !same_trace(turns) {
            return 4
        }
        // 1 + 2 + ... + 256
        if turns.deep_sum != 32896 || !turns.deep_on_segment {
            return 5
        }
        if segments_cached(carrier) != SEGMENT_COUNT {
            return 6
        }
        // Each fiber was one allocation, freed once it finished
        if arena.live != live_before - 3 {
            return 7
        }
        if carrier.current_fiber != null || carrier.yield_function != null {
            return 8
        }
    }
    return 42
}
