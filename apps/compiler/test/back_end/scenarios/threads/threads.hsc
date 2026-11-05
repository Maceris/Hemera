/*
 * Threads and fiber pools in a hosted program on Windows, run by one test.
 *
 * The test's thread, the program's main one, runs no pool. Threads 1 and 2 share the first pool, threads 3 to 5 the second, and thread 6
 * runs none. The pools' threads start before there's any work, so they go to sleep, and the test's
 * spawning wakes them. Each fiber takes TURNS turns, yielding after each, and records which threads
 * it ran on: it has to stay on its own pool's threads, every thread of a pool has to run some, and
 * some have to move between threads, which fibers that have taken their turns wait for
 * (take_turns), so it doesn't depend on timing.
 *
 * Every turn also adds one to a counter behind a std/concurrency Mutex, yielding while it holds it,
 * so other fibers park waiting for it, and the test and thread 6 add to it too, blocking instead.
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
import testing from "std"

FIRST_FIBERS :: 40
SECOND_FIBERS :: 60
TURNS :: 50
// How long a fiber that has taken its turns waits for the rest of its pool's threads to run one,
// and for one to move
WAIT_YIELDS :: 1000000
// The threads each pool runs on, a bit per thread index: 1 and 2, and 3 to 5
FIRST_THREADS : u64 : 0b000110
SECOND_THREADS : u64 : 0b111000
POOL_THREADS :: 5
// Thread 6 runs no pool
PLAIN_THREAD :: 6
// What the test and thread 6 each add to the counter
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

shares_work_among_threads_and_fiber_pools #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // The main thread runs no pool: yielding does nothing
    runtime.fiber_yield()
    test :: runtime.new(ThreadTest)
    test.first = fiber.create_fiber_pool()
    test.second = fiber.create_fiber_pool()
    threads : rawptr[7]
    push_context with_test (user_data = cast[rawptr](test)) {
        for i in 1..<7 {
            thread :: runtime.thread_create(if i == PLAIN_THREAD { plain_main } else { carrier_main })
            thread.index = cast[usize](i)
            testing.require(t, runtime.thread_start(thread), "the system starts each of six threads")?
            threads[i] = cast[rawptr](thread)
        }
        // Once the pools' threads have started, and gone to sleep, the work
        loop {
            intrinsics.spin_hint()
        }
        while intrinsics.atomic_load_u64_acquire(&test.started) < POOL_THREADS
        _, deep_error :: fiber.spawn(test.first, deep_worker)
        testing.require(t, deep_error == null, "the deep fiber is spawned")?
        for i in 0..<PRODUCERS {
            _, error :: fiber.spawn(test.first, producer_worker)
            testing.require(t, error == null, "each producer fiber is spawned")?
        }
        for i in 0..<CONSUMERS {
            _, error :: fiber.spawn(test.second, consumer_worker)
            testing.require(t, error == null, "each consumer fiber is spawned")?
        }
        for i in 0..<FIRST_FIBERS {
            _, error :: fiber.spawn(test.first, first_worker)
            testing.require(t, error == null, "each of the first pool's fibers is spawned")?
        }
        for i in 0..<SECOND_FIBERS {
            _, error :: fiber.spawn(test.second, second_worker)
            testing.require(t, error == null, "each of the second pool's fibers is spawned")?
        }
        fiber.close_pool(test.first)
        fiber.close_pool(test.second)
        // The main thread runs no pool, so it blocks when it has to wait
        for i in 0..<PLAIN_ADDS {
            add_one(test)
        }
    }
    for i in 1..<7 {
        runtime.thread_join(cast[ptr[mut runtime.Thread]](threads[i]))
    }
    expect_counts(t, &test.first_counts, FIRST_FIBERS, FIRST_THREADS)
    expect_counts(t, &test.second_counts, SECOND_FIBERS, SECOND_THREADS)
    testing.expect_ne(t, test.first_counts.moves + test.second_counts.moves, 0, "fibers waiting for a move make some move between threads")
    testing.expect_eq(t, test.plain_index, PLAIN_THREAD, "the thread without a pool has the index it was given")
    testing.expect_eq(t, test.plain_yielded, 1, "yielding without a pool comes straight back")
    testing.expect_eq(t, test.counter, (FIRST_FIBERS + SECOND_FIBERS) * TURNS + 2 * PLAIN_ADDS,
        "the mutex lets no addition be lost, though each yields between its read and its write")
    testing.expect_eq(t, test.fiber_sum, FIBER_DEPTH * (FIBER_DEPTH + 1) / 2, "a fiber's stack grows onto new segments for deep calls")
    testing.expect_eq(t, test.thread_sum, THREAD_DEPTH * (THREAD_DEPTH + 1) / 2, "a thread's stack grows well past what the system gave it")
    testing.expect_eq(t, test.received_count, PRODUCERS * ITEMS_EACH, "every value sent through the channel is received once")
    testing.expect_eq(t, test.received_sum, PRODUCERS * ITEMS_EACH * (ITEMS_EACH + 1) / 2, "each value is received as it was sent")
    fiber.destroy_fiber_pool(test.first)
    fiber.destroy_fiber_pool(test.second)
    return .Ok
}

/**
 * Check what one pool's fibers recorded: every turn taken, none away from the pool's threads, and every one of them used.
 *
 * @param t The test's state, which failures are recorded in.
 * @param counts What the pool's fibers recorded.
 * @param fibers How many fibers the pool ran.
 * @param threads The pool's threads, a bit per thread index.
 * @param location Where the check is, the caller's own, which tells the pools apart.
 */
expect_counts :: fn(t: ptr[mut testing.T], counts: ptr[PoolCounts], fibers: u64, threads: u64,
    location := #caller_location) {
    testing.expect_eq(t, counts.turns, fibers * TURNS, "every fiber takes all its turns", location)
    testing.expect_eq(t, counts.strays, 0, "a fiber stays on its own pool's threads", location)
    testing.expect_eq(t, counts.threads, threads, "every thread of a pool runs some of its fibers, and only those", location)
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

/*
 * TURNS turns, then yielding until every one of the pool's threads has run one of its fibers and
 * one has moved, or WAIT_YIELDS yields. A thread counts as started before it joins its pool, so
 * with few CPUs it can join after the others have taken every turn: waiting here keeps fibers in
 * the queue for it, rather than relying on the operating system to run it in time. These yields
 * aren't turns, but are recorded the same way, so they still have to stay on the pool's threads.
 */
take_turns :: fn(counts: ptr[mut PoolCounts], threads: u64) {
    previous := runtime.current_thread_index()
    for turn in 0..<TURNS {
        previous = record(counts, threads, previous)
        intrinsics.interlocked_increment_u64(&counts.turns)
        add_one(cast[ptr[mut ThreadTest]](context.user_data))
        runtime.fiber_yield()
    }
    for i in 0..<WAIT_YIELDS {
        if intrinsics.atomic_load_u64_acquire(&counts.threads) & threads == threads
            && intrinsics.atomic_load_u64_acquire(&counts.moves) != 0 {
            break
        }
        runtime.fiber_yield()
        previous = record(counts, threads, previous)
    }
}

// Which thread this is, for the next time, after counting it in counts.
record :: fn(counts: ptr[mut PoolCounts], threads: u64, previous: usize) -> usize {
    here :: runtime.current_thread_index()
    bit :: cast[u64](1) << cast[u64](here)
    if bit & threads == 0 {
        intrinsics.interlocked_increment_u64(&counts.strays)
    }
    if here != previous {
        intrinsics.interlocked_increment_u64(&counts.moves)
    }
    intrinsics.interlocked_or_u64(&counts.threads, bit)
    return here
}
