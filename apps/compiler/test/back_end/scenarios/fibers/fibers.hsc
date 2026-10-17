/*
 * Fibers in a hosted program on Windows, run by a std/fiber pool with this thread as its one
 * carrier: main returns 42 if everything worked, or the number of the first check that failed.
 * Built with stack_check = .Morestack, so a fiber that recurses deeply grows onto segments.
 *
 * Foreign calls run on the thread's own stack, from main and from a fiber. Foreign code calls back
 * into Hemera, with the caller's context, from main, from a fiber, and on a thread Hemera didn't
 * start. Memory comes from an arena in main's frame.
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
    // What RtlCaptureContext saw, from a fiber
    windows_context : WindowsContext,
    // Where main's arena starts: fibers' stacks are above it, and the thread's below
    arena_start : u64,
    // main's thread, which the fibers run on too
    thread : u32,
    // From the fiber that calls foreign functions: 0 once they all worked, or the first that didn't
    foreign_failure : int,
    // Callbacks counted, and what the fiber's enumeration counted
    code_pages : u64,
    fiber_code_pages : u64,
    // What the thread Hemera didn't start saw: its carrier block, and a value from the heap
    foreign_thread_carrier : u64,
    foreign_thread_value : u64,
}

// Callbacks from foreign code: EnumSystemCodePagesA calls code_page once for each installed code page
CP_INSTALLED : u32 : 1
EnumSystemCodePagesA #foreign(KERNEL32) : fn(callback: rawptr, flags: u32) -> i32 : ---
create_thread #foreign(KERNEL32) #link_name("CreateThread") : fn(
    attributes: rawptr,
    stack_size: usize,
    start: rawptr,
    parameter: rawptr,
    flags: u32,
    id: rawptr,
) -> rawptr : ---
WaitForSingleObject #foreign(KERNEL32) : fn(handle: rawptr, milliseconds: u32) -> u32 : ---
CloseHandle #foreign(KERNEL32) : fn(handle: rawptr) -> i32 : ---

// A callback with the context of whoever called EnumSystemCodePagesA, which has the Turns.
code_page #calling_convention(.c) :: fn(name: rawptr) -> i32 {
    turns :: cast[ptr[mut Turns]](context.user_data)
    turns.code_pages += 1
    return 1
}

count_code_pages :: fn(turns: ptr[mut Turns]) -> u64 {
    turns.code_pages = 0
    EnumSystemCodePagesA(cast[rawptr](code_page), CP_INSTALLED)
    return turns.code_pages
}

/*
 * Where a thread Hemera didn't start runs: it gets a carrier block of its own and HOSTED_CONTEXT,
 * with the process heap, which new uses.
 */
foreign_thread #calling_convention(.c) :: fn(parameter: rawptr) -> u32 {
    turns :: cast[ptr[mut Turns]](parameter)
    turns.foreign_thread_carrier = cast[u64](intrinsics.carrier())
    made :: runtime.new(u64)
    made^ = 7
    // HOSTED_CONTEXT has no user_data
    extra :: if context.user_data == null { cast[u64](1) } else { cast[u64](100) }
    turns.foreign_thread_value = made^ + extra
    runtime.free(made)
    return 0
}

// Foreign functions, from two libraries
KERNEL32 :: #library("kernel32")
NTDLL :: #library("ntdll")

GetCurrentThreadId #foreign(KERNEL32) : fn() -> u32 : ---
SetLastError #foreign(KERNEL32) : fn(code: u32) : ---
GetLastError #foreign(KERNEL32) : fn() -> u32 : ---
// Six arguments: the last two on the stack
multi_byte_to_wide_char #foreign(KERNEL32) #link_name("MultiByteToWideChar") : fn(
    code_page: u32,
    flags: u32,
    text: rawptr,
    count: i32,
    wide: ptr[mut u16],
    wide_count: i32,
) -> i32 : ---
RtlCaptureContext #foreign(NTDLL) : fn(context: ptr[mut WindowsContext]) : ---

// Windows' CONTEXT, of which only the stack pointer is read.
WindowsContext :: struct #align(16) {
    bytes : u8[1232],
}
CONTEXT_RSP :: 0x98

// The stack pointer RtlCaptureContext saw.
captured_rsp :: fn(context: ptr[WindowsContext]) -> u64 {
    return cast[ptr[u64]](cast[rawptr](cast[u64](&context.bytes) + CONTEXT_RSP))^
}

/*
 * Foreign calls, with a result, with arguments on the stack, and keeping the thread's last error
 * between calls: 0 if they all worked, or the number of the first that didn't.
 */
call_foreign :: fn(thread: u32) -> int {
    if GetCurrentThreadId() != thread {
        return 1
    }
    SetLastError(1234)
    if GetLastError() != 1234 {
        return 2
    }
    text : string : "fibers"
    wide : u16[8]
    // CP_UTF8
    if multi_byte_to_wide_char(65001, 0, text.data, 6, &wide[0], 8) != 6 || wide[0] != 102 || wide[5] != 115 {
        return 3
    }
    return 0
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

// Foreign calls from a fiber: they run below the arena, on the thread's own stack, not on the fiber's.
worker_foreign : runtime.ThreadFunction : fn(data #escaping : any) {
    turns :: cast[ptr[mut Turns]](context.user_data)
    limit :: intrinsics.carrier().stack_limit
    turns.foreign_failure = call_foreign(turns.thread)
    // Called back on the thread's own stack, with this fiber's context
    turns.fiber_code_pages = count_code_pages(turns)
    RtlCaptureContext(&turns.windows_context)
    if turns.foreign_failure == 0 && captured_rsp(&turns.windows_context) >= turns.arena_start {
        turns.foreign_failure = 4
    }
    if turns.foreign_failure == 0 && intrinsics.carrier().stack_limit != limit {
        turns.foreign_failure = 5
    }
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
        turns.arena_start = cast[u64](&arena.bytes)
        turns.thread = GetCurrentThreadId()
        turns.foreign_failure = -1
        // From main, on the thread's stack already
        if call_foreign(turns.thread) != 0 {
            return 9
        }
        main_code_pages : u64 = 0
        push_context with_turns (user_data = cast[rawptr](turns)) {
            main_code_pages = count_code_pages(turns)
        }
        if main_code_pages == 0 {
            return 21
        }
        thread :: create_thread(null, 0, cast[rawptr](foreign_thread), cast[rawptr](turns), 0, null)
        if thread == null {
            return 22
        }
        WaitForSingleObject(thread, 0xffffffff)
        CloseHandle(thread)
        if turns.foreign_thread_value != 8 || turns.foreign_thread_carrier == 0 || turns.foreign_thread_carrier == cast[u64](carrier) {
            return 23
        }
        live_before :: arena.live
        pool :: fiber.create_fiber_pool()
        push_context with_turns (user_data = cast[rawptr](turns)) {
            _, error_a :: fiber.spawn(pool, worker_a)
            _, error_b :: fiber.spawn(pool, worker_b)
            _, error_deep :: fiber.spawn(pool, worker_deep)
            _, error_foreign :: fiber.spawn(pool, worker_foreign)
            if error_a != null || error_b != null || error_deep != null || error_foreign != null {
                return 2
            }
        }
        fiber.close_pool(pool)
        fiber.run_carrier(pool)
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
        // Each fiber was freed once it finished, and the pool and its carrier's part now
        fiber.destroy_fiber_pool(pool)
        if arena.live != live_before {
            return 7
        }
        if carrier.current_fiber != null || carrier.yield_function != null {
            return 8
        }
        if turns.foreign_failure != 0 {
            return 10 + turns.foreign_failure
        }
        if carrier.foreign_depth != 0 {
            return 20
        }
        if turns.fiber_code_pages != main_code_pages {
            return 24
        }
    }
    return 42
}
