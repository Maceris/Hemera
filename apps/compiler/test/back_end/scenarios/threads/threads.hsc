/*
 * Threads and fiber pools in a hosted program on Windows: main returns 42 if everything worked, or
 * the number of the first check that failed.
 *
 * main runs no pool. Threads 1 and 2 share the first pool, threads 3 to 5 the second, and thread 6
 * runs none. The pools' threads start before there's any work, so they go to sleep, and main's
 * spawning wakes them. Each fiber takes TURNS turns, yielding after each, and records which threads
 * it ran on: it has to stay on its own pool's threads, and every thread of a pool has to run some.
 *
 * Every turn also adds one to a counter behind a std/concurrency Mutex, yielding while it holds it,
 * so other fibers park waiting for it, and main and thread 6 add to it too, blocking instead.
 *
 * Values go through a std/concurrency Channel of 8, from PRODUCERS fibers of the first pool to
 * CONSUMERS fibers of the second and to thread 6, so senders and receivers both wait, on fibers and
 * on a thread. The last producer closes it.
 *
 * Built with stack_check = .Morestack. Nothing fills the carriers' segment caches, so growing
 * allocates segments: a fiber of the first pool recurses FIBER_DEPTH calls deep, and thread 6
 * THREAD_DEPTH, well past the stack the system gave it.
 */
package threads

import intrinsics from "base"
import runtime from "base"
import fiber from "std"
import concurrency from "std"

FIRST_FIBERS :: 40
SECOND_FIBERS :: 60
TURNS :: 50
// The threads each pool runs on, a bit per thread index: 1 and 2, and 3 to 5
FIRST_THREADS : u64 : 0b000110
SECOND_THREADS : u64 : 0b111000
POOL_THREADS :: 5
// Thread 6 runs no pool
PLAIN_THREAD :: 6
// What main and thread 6 each add to the counter
PLAIN_ADDS :: 500
// About 64 bytes a call: 192 KiB on a fiber, and 4 MiB on thread 6, whose own stack is 1 MiB
FIBER_DEPTH :: 3000
PRODUCERS :: 6
CONSUMERS :: 4
ITEMS_EACH :: 200
THREAD_DEPTH :: 65536

// What one pool's fibers record.
PoolCounts :: struct {
    turns : u64,
    // A bit per thread index
    threads : u64,
    // Turns on a different thread than the fiber's previous turn
    moves : u64,
    // Turns on a thread outside the pool
    strays : u64,
}

ThreadTest :: struct {
    first : ptr[mut fiber.FiberPool],
    second : ptr[mut fiber.FiberPool],
    first_counts : PoolCounts,
    second_counts : PoolCounts,
    // Pool threads that have started
    started : u64,
    // What the thread without a pool saw
    plain_index : u64,
    plain_yielded : u64,
    // Only changed with counter_lock held, and read and written in separate steps around a yield
    counter_lock : concurrency.Mutex,
    counter : u64,
    // What the deep calls added up to
    fiber_sum : u64,
    thread_sum : u64,
    channel : concurrency.Channel[u64, 8],
    producers_done : u64,
    received_sum : u64,
    received_count : u64,
}

producer_worker : runtime.ThreadFunction : fn(data #escaping : any) {
    test :: cast[ptr[mut ThreadTest]](context.user_data)
    for i in 0..<ITEMS_EACH {
        concurrency.channel_send(&test.channel, cast[u64](i + 1))
    }
    // The last one closes it (the count from before comes back)
    if intrinsics.interlocked_increment_u64(&test.producers_done) == PRODUCERS - 1 {
        concurrency.channel_close(&test.channel)
    }
}

// Until the channel is closed and empty.
consume :: fn(test: ptr[mut ThreadTest]) {
    loop {
        value, ok :: concurrency.channel_receive(&test.channel)
        if !ok {
            break
        }
        intrinsics.interlocked_exchange_add_u64(&test.received_sum, value)
        intrinsics.interlocked_increment_u64(&test.received_count)
    }
}

consumer_worker : runtime.ThreadFunction : fn(data #escaping : any) {
    consume(cast[ptr[mut ThreadTest]](context.user_data))
}

// 1 + 2 + ... + depth, a call each, reading back after the call so it isn't turned into a loop.
climb :: fn(depth: u64, last: u64) -> u64 {
    padding : u64[4]
    intrinsics.volatile_store_u64(&padding[0], depth)
    if depth == last {
        return depth
    }
    below :: climb(depth + 1, last)
    return below + intrinsics.volatile_load_u64(&padding[0])
}

deep_worker : runtime.ThreadFunction : fn(data #escaping : any) {
    test :: cast[ptr[mut ThreadTest]](context.user_data)
    test.fiber_sum = climb(1, FIBER_DEPTH)
}

// One more on the counter: read, yield (or not, on a thread), write, all with the lock held.
add_one :: fn(test: ptr[mut ThreadTest]) {
    concurrency.mutex_lock(&test.counter_lock)
    defer concurrency.mutex_unlock(&test.counter_lock)
    before :: test.counter
    runtime.fiber_yield()
    test.counter = before + 1
}

main :: fn() -> int {
    // main runs no pool: yielding does nothing
    runtime.fiber_yield()
    test :: runtime.new(ThreadTest)
    test.first = fiber.create_fiber_pool()
    test.second = fiber.create_fiber_pool()
    threads : rawptr[7]
    push_context with_test (user_data = cast[rawptr](test)) {
        for i in 1..<7 {
            thread :: runtime.thread_create(if i == PLAIN_THREAD { plain_main } else { carrier_main })
            thread.index = cast[usize](i)
            if !runtime.thread_start(thread) {
                return 1
            }
            threads[i] = cast[rawptr](thread)
        }
        // Once the pools' threads have started, and gone to sleep, the work
        loop {
            intrinsics.spin_hint()
        }
        while intrinsics.atomic_load_u64_acquire(&test.started) < POOL_THREADS
        _, deep_error :: fiber.spawn(test.first, deep_worker)
        if deep_error != null {
            return 2
        }
        for i in 0..<PRODUCERS {
            _, error :: fiber.spawn(test.first, producer_worker)
            if error != null {
                return 2
            }
        }
        for i in 0..<CONSUMERS {
            _, error :: fiber.spawn(test.second, consumer_worker)
            if error != null {
                return 2
            }
        }
        for i in 0..<FIRST_FIBERS {
            _, error :: fiber.spawn(test.first, first_worker)
            if error != null {
                return 2
            }
        }
        for i in 0..<SECOND_FIBERS {
            _, error :: fiber.spawn(test.second, second_worker)
            if error != null {
                return 2
            }
        }
        fiber.close_pool(test.first)
        fiber.close_pool(test.second)
        // main runs no pool, so it blocks when it has to wait
        for i in 0..<PLAIN_ADDS {
            add_one(test)
        }
    }
    for i in 1..<7 {
        runtime.thread_join(cast[ptr[mut runtime.Thread]](threads[i]))
    }
    if !counts_ok(&test.first_counts, FIRST_FIBERS, FIRST_THREADS) {
        return 3
    }
    if !counts_ok(&test.second_counts, SECOND_FIBERS, SECOND_THREADS) {
        return 4
    }
    if test.first_counts.moves + test.second_counts.moves == 0 {
        return 5
    }
    if test.plain_index != PLAIN_THREAD || test.plain_yielded != 1 {
        return 6
    }
    if test.counter != (FIRST_FIBERS + SECOND_FIBERS) * TURNS + 2 * PLAIN_ADDS {
        return 7
    }
    if test.fiber_sum != FIBER_DEPTH * (FIBER_DEPTH + 1) / 2 {
        return 8
    }
    if test.thread_sum != THREAD_DEPTH * (THREAD_DEPTH + 1) / 2 {
        return 9
    }
    if test.received_count != PRODUCERS * ITEMS_EACH || test.received_sum != PRODUCERS * ITEMS_EACH * (ITEMS_EACH + 1) / 2 {
        return 10
    }
    fiber.destroy_fiber_pool(test.first)
    fiber.destroy_fiber_pool(test.second)
    return 42
}

counts_ok :: fn(counts: ptr[PoolCounts], fibers: u64, threads: u64) -> bool {
    return counts.turns == fibers * TURNS && counts.strays == 0 && counts.threads == threads
}

// A pool's thread: the pool its index says, until it's closed and its fibers have finished.
carrier_main : runtime.ThreadFunction : fn(data #escaping : any) {
    test :: cast[ptr[mut ThreadTest]](context.user_data)
    bit :: cast[u64](1) << cast[u64](runtime.current_thread_index())
    pool :: if bit & FIRST_THREADS != 0 { test.first } else { test.second }
    intrinsics.interlocked_increment_u64(&test.started)
    fiber.run_carrier(pool)
}

// The thread without a pool: yielding does nothing here either.
plain_main : runtime.ThreadFunction : fn(data #escaping : any) {
    test :: cast[ptr[mut ThreadTest]](context.user_data)
    test.plain_index = cast[u64](runtime.current_thread_index())
    runtime.fiber_yield()
    test.plain_yielded = 1
    test.thread_sum = climb(1, THREAD_DEPTH)
    // A thread receiving too, blocking while the channel is empty
    consume(test)
    for i in 0..<PLAIN_ADDS {
        add_one(test)
    }
}

first_worker : runtime.ThreadFunction : fn(data #escaping : any) {
    test :: cast[ptr[mut ThreadTest]](context.user_data)
    take_turns(&test.first_counts, FIRST_THREADS)
}

second_worker : runtime.ThreadFunction : fn(data #escaping : any) {
    test :: cast[ptr[mut ThreadTest]](context.user_data)
    take_turns(&test.second_counts, SECOND_THREADS)
}

take_turns :: fn(counts: ptr[mut PoolCounts], threads: u64) {
    previous := runtime.current_thread_index()
    for turn in 0..<TURNS {
        here :: runtime.current_thread_index()
        bit :: cast[u64](1) << cast[u64](here)
        if bit & threads == 0 {
            intrinsics.interlocked_increment_u64(&counts.strays)
        }
        if here != previous {
            intrinsics.interlocked_increment_u64(&counts.moves)
        }
        intrinsics.interlocked_or_u64(&counts.threads, bit)
        intrinsics.interlocked_increment_u64(&counts.turns)
        previous = here
        add_one(cast[ptr[mut ThreadTest]](context.user_data))
        runtime.fiber_yield()
    }
}
