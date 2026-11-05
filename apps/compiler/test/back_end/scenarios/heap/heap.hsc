/*
 * The hosted context's allocator, from several threads at once. On Linux that's the runtime's own heap
 * (PageHeap), on Windows the process heap.
 *
 * Each thread allocates blocks of many sizes and alignments, checks that each is aligned and
 * zeroed, fills it with its own pattern, frees every other one, allocates again, and then checks
 * that no block's pattern changed, so no two blocks overlap.
 */
package heap

import intrinsics from "base"
import runtime from "base"
import testing from "std"

/** How many blocks each thread holds at once. */
BLOCKS : usize : 300
/** How many threads allocate at once. */
THREADS : usize : 4
/** How many times each thread allocates its blocks and frees them all. */
ROUNDS :: 3

/** What went wrong with a thread's blocks, or that nothing did. */
Problem :: enum {
    /** Every block was allocated, aligned, zeroed and kept its pattern. */
    None,
    /** An allocation failed, or gave a block of another size. */
    NotAllocated,
    /** A block wasn't at a multiple of its alignment. */
    Misaligned,
    /** A new block's bytes weren't all zero. */
    NotZeroed,
    /** A block's pattern changed while it was held: another block overlapped it. */
    Overwritten,
}

/** What one thread found. */
Report :: struct {
    /** None, or the first problem the thread had. */
    problem : Problem,
}

/** One block, as allocated. */
Block :: struct {
    /** The block's bytes, size_of_block of them. */
    bytes : u8[],
}

/** What the threads share, through context.user_data. */
Shared :: struct {
    /** Each thread's report, by the index it took from next. */
    reports : Report[THREADS],
    /** The next thread's index, taken with an interlocked increment. */
    next : u64,
}

/**
 * Give the size of a thread's block number i.
 *
 * @param i The block's number.
 * @return From 1 to 6000 bytes.
 */
size_of_block :: fn(i: usize) -> usize {
    return (i * 37) % 6000 + 1
}

/**
 * Give the alignment of a thread's block number i.
 *
 * @param i The block's number.
 * @return A power of two from 1 to 4096.
 */
alignment_of_block :: fn(i: usize) -> usize {
    return cast[usize](1) << ((i * 7) % 13)
}

/**
 * Give the byte a thread fills its block number i with, different for each thread and block.
 *
 * @param thread The thread's number.
 * @param i The block's number.
 * @return A byte from 2 to 252, never zero.
 */
pattern :: fn(thread: usize, i: usize) -> u8 {
    return cast[u8]((thread * 31 + i * 7 + 1) % 251 + 1)
}

/**
 * Set every byte of a block.
 *
 * @param block The block, changed in place.
 * @param value What each byte is set to.
 */
fill :: fn(block: mut u8[], value: u8) {
    for i in 0..<block.count {
        block[i] = value
    }
}

/**
 * Tell whether every byte of a block is a value.
 *
 * @param block The block, only read.
 * @param value The byte looked for.
 * @return True if every byte is value, or the block is empty.
 */
holds :: fn(block: u8[], value: u8) -> bool {
    for i in 0..<block.count {
        if block[i] != value {
            return false
        }
    }
    return true
}

/**
 * Allocate a thread's block number i, check it, fill it with its pattern and keep it.
 *
 * @param thread The thread's number.
 * @param i The block's number, below BLOCKS.
 * @param blocks Where the block is kept, at i.
 * @return None if it was allocated whole, aligned and zeroed; otherwise what was wrong, and the block isn't kept.
 */
allocate :: fn(thread: usize, i: usize, blocks: ptr[mut Block[BLOCKS]]) -> Problem {
    size :: size_of_block(i)
    alignment :: alignment_of_block(i)
    block, error :: runtime.new_array_aligned(u8, size, alignment)
    if error != null || block.count != size {
        return .NotAllocated
    }
    if cast[usize](block.data) & (alignment - 1) != 0 {
        return .Misaligned
    }
    if !holds(block, 0) {
        return .NotZeroed
    }
    fill(block, pattern(thread, i))
    if i < BLOCKS {
        blocks^[i].bytes = block
    }
    return .None
}

/**
 * Allocate and free a thread's blocks for ROUNDS rounds, checking each block.
 *
 * @param thread The thread's number, which picks its blocks' patterns.
 * @return None if every block was right; otherwise the first problem, with the blocks held then not freed.
 */
exercise :: fn(thread: usize) -> Problem {
    blocks : Block[BLOCKS]
    for round in 0..<ROUNDS {
        for i in 0..<BLOCKS {
            problem :: allocate(thread, i, &blocks)
            if problem != .None {
                return problem
            }
        }
        // Every other one back, and again
        for i in 0..<BLOCKS {
            if i % 2 == 0 {
                runtime.free_array_aligned(blocks[i].bytes, alignment_of_block(i))
                problem :: allocate(thread, i, &blocks)
                if problem != .None {
                    return problem
                }
            }
        }
        for i in 0..<BLOCKS {
            if !holds(blocks[i].bytes, pattern(thread, i)) {
                return .Overwritten
            }
        }
        for i in 0..<BLOCKS {
            runtime.free_array_aligned(blocks[i].bytes, alignment_of_block(i))
        }
    }
    return .None
}

/** A thread exercising its blocks, reporting into the Shared in context.user_data at the index it takes. */
worker : runtime.ThreadFunction : fn(data #escaping : any) {
    shared :: cast[ptr[mut Shared]](context.user_data)
    index :: cast[usize](intrinsics.interlocked_increment_u64(&shared.next))
    if index < THREADS {
        shared.reports[index].problem = exercise(index + 1)
    }
}

allocates_on_one_thread #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, exercise(0), Problem.None, "each block is allocated whole, aligned, zeroed and apart from the rest")
    return .Ok
}

allocates_from_several_threads_at_once #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    shared :: runtime.new(Shared)
    defer runtime.free(shared)
    threads : rawptr[THREADS]
    started : usize = 0
    push_context with_shared (user_data = cast[rawptr](shared)) {
        for i in 0..<THREADS {
            thread :: runtime.thread_create(worker)
            thread.index = i + 1
            if !testing.expect(t, runtime.thread_start(thread), "the system starts a thread") {
                break
            }
            threads[i] = cast[rawptr](thread)
            started += 1
        }
    }
    for i in 0..<started {
        if i < THREADS {
            runtime.thread_join(cast[ptr[mut runtime.Thread]](threads[i]))
        }
    }
    testing.require_eq(t, started, THREADS, "every thread started")?
    for report in shared.reports {
        testing.expect_eq(t, report.problem, Problem.None, "the allocator keeps each thread's blocks whole and apart")
    }
    return .Ok
}
