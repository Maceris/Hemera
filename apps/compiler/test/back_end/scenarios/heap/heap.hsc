/*
 * The hosted context's allocator, from several threads at once: main returns 42 if everything
 * worked, or the number of the first check that failed. On Linux that's the runtime's own heap
 * (PageHeap), on Windows the process heap.
 *
 * Each thread allocates blocks of many sizes and alignments, checks that each is aligned and
 * zeroed, fills it with its own pattern, frees every other one, allocates again, and then checks
 * that no block's pattern changed, so no two blocks overlap.
 */
package heap

import intrinsics from "base"
import runtime from "base"

BLOCKS : usize : 300
THREADS : usize : 4
ROUNDS :: 3

// What one thread found: 0, or the number of the first check that failed.
Report :: struct {
    failure : u64,
}

// One block, as allocated
Block :: struct {
    bytes : u8[],
}

Shared :: struct {
    reports : Report[THREADS],
    next : u64,
}

// The size and alignment of a thread's block number i: up to about 6 KiB, aligned 1 to 4096.
size_of_block :: fn(i: usize) -> usize {
    return (i * 37) % 6000 + 1
}

alignment_of_block :: fn(i: usize) -> usize {
    return cast[usize](1) << ((i * 7) % 13)
}

// A byte that's different for each thread and block.
pattern :: fn(thread: usize, i: usize) -> u8 {
    return cast[u8]((thread * 31 + i * 7 + 1) % 251 + 1)
}

fill :: fn(block: u8[], value: u8) {
    for i in 0..<block.count {
        block[i] = value
    }
}

holds :: fn(block: u8[], value: u8) -> bool {
    for i in 0..<block.count {
        if block[i] != value {
            return false
        }
    }
    return true
}

allocate :: fn(thread: usize, i: usize, blocks: ptr[mut Block[BLOCKS]]) -> u64 {
    size :: size_of_block(i)
    alignment :: alignment_of_block(i)
    block, error :: runtime.new_array_aligned(u8, size, alignment)
    if error != null || block.count != size {
        return 1
    }
    if cast[usize](block.data) & (alignment - 1) != 0 {
        return 2
    }
    if !holds(block, 0) {
        return 3
    }
    fill(block, pattern(thread, i))
    if i < BLOCKS {
        blocks^[i].bytes = block
    }
    return 0
}

exercise :: fn(thread: usize) -> u64 {
    blocks : Block[BLOCKS]
    for round in 0..<ROUNDS {
        for i in 0..<BLOCKS {
            failure :: allocate(thread, i, &blocks)
            if failure != 0 {
                return failure
            }
        }
        // Every other one back, and again
        for i in 0..<BLOCKS {
            if i % 2 == 0 {
                runtime.free_array(blocks[i].bytes)
                failure :: allocate(thread, i, &blocks)
                if failure != 0 {
                    return failure
                }
            }
        }
        for i in 0..<BLOCKS {
            if !holds(blocks[i].bytes, pattern(thread, i)) {
                return 4
            }
        }
        for i in 0..<BLOCKS {
            runtime.free_array(blocks[i].bytes)
        }
    }
    return 0
}

worker : runtime.ThreadFunction : fn(data #escaping : any) {
    shared :: cast[ptr[mut Shared]](context.user_data)
    index :: cast[usize](intrinsics.interlocked_increment_u64(&shared.next))
    if index < THREADS {
        shared.reports[index].failure = exercise(index + 1)
    }
}

main :: fn() -> int {
    // On one thread first
    alone :: exercise(0)
    if alone != 0 {
        return cast[int](alone)
    }
    shared :: runtime.new(Shared)
    threads : rawptr[THREADS]
    push_context with_shared (user_data = cast[rawptr](shared)) {
        for i in 0..<THREADS {
            thread :: runtime.thread_create(worker)
            thread.index = i + 1
            if !runtime.thread_start(thread) {
                return 10
            }
            threads[i] = cast[rawptr](thread)
        }
    }
    for i in 0..<THREADS {
        runtime.thread_join(cast[ptr[mut runtime.Thread]](threads[i]))
    }
    for i in 0..<THREADS {
        if shared.reports[i].failure != 0 {
            return 20 + cast[int](shared.reports[i].failure)
        }
    }
    return 42
}
