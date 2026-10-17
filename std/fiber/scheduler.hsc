package fiber

import intrinsics from "base"
import runtime from "base"
import concurrency from "std"

/*
 * A pool of fibers that one or more carriers share (docs/multitasking.md, Fiber Pools). Each thread
 * chooses whether to run a pool: a program can have threads without one, and any number of pools,
 * each run by its own set of threads.
 *
 *     pool :: fiber.create_fiber_pool()
 *     fiber.spawn(pool, worker, data)
 *     fiber.close_pool(pool)
 *     // On each thread that runs the pool, until it's closed and every fiber has finished
 *     fiber.run_carrier(pool)
 *
 * Each carrier keeps a queue of its own, and the pool has a shared one. A carrier runs fibers
 * from its own queue, then from the shared queue, taking a share of what's there, and with
 * nothing left, takes half of another carrier's queue. A fiber that yields goes to the back of
 * the shared queue, so any carrier can resume it. Fibers spawned on one of the pool's fibers go
 * to that carrier's queue, the others to the shared one.
 *
 * Fibers start with a copy of the context of whoever spawned them, and are made and freed with
 * the pool's allocator, which the carriers use at the same time, so it has to be safe for that.
 *
 * A carrier with nothing to run spins a little, then sleeps (runtime.wait_on_value) until work
 * is added, the pool closes, or its last fiber finishes. Without an operating system to sleep on,
 * it keeps spinning, which suits a kernel that gives a pool its own CPUs.
 *
 * A fiber that parks (runtime.park, which locks like std/concurrency's Mutex use) is suspended
 * and left out of the queues until runtime.wake, from any thread, puts it back in the shared queue.
 */
FiberPool :: struct {
    // What the pool's fibers point to, for runtime.wake: first, so a fiber's scheduler is its pool
    scheduler : runtime.FiberScheduler,
    // Guards the shared queue, and the list of carriers while one joins
    lock : concurrency.SpinLock,
    // The shared queue, linked through Fiber.next, first to run first
    first : ptr[mut runtime.Fiber]?,
    last : ptr[mut runtime.Fiber]?,
    // How many fibers are in the shared queue: written under the lock, read without it
    shared_count : u64,
    // Fibers spawned that haven't finished
    live : u64,
    // Set by close_pool: once no fiber is live, carriers leave
    closed : u64,
    // Every carrier that has joined, as ptr[mut PoolCarrier]: carrier_count of them
    carriers : rawptr[MAX_CARRIERS],
    carrier_count : u64,
    // Carriers running the pool now
    active_carriers : u64,
    // Changes whenever there's something for a sleeping carrier to look at, which it sleeps on
    work_epoch : u32,
    // Carriers asleep, or about to be, so adding work only wakes one when there is one
    sleepers : u64,
    allocator : runtime.Allocator,
}

// The most carriers one pool can have.
MAX_CARRIERS :: 64
// The size of a carrier's own queue, a power of two, so a position masked is its slot.
LOCAL_QUEUE_SIZE :: 256
LOCAL_QUEUE_MASK :: LOCAL_QUEUE_SIZE - 1
// Every this many turns, a carrier looks at the shared queue first, so it isn't left waiting.
SHARED_QUEUE_INTERVAL :: 61
// How many times a carrier with nothing to run looks again before it sleeps.
IDLE_SPINS :: 64

/*
 * One carrier's part of a pool, the carrier block's scheduler_data while it runs the pool. Kept
 * until the pool is destroyed, since other carriers may be looking at its queue.
 */
PoolCarrier :: struct {
    pool : ptr[mut FiberPool],
    /*
     * The carrier's own queue, a ring: the carrier adds at tail and takes at head, and other
     * carriers take at head too, so head only moves by compare and exchange. Neither wraps.
     */
    head : u64,
    tail : u64,
    queue : rawptr[LOCAL_QUEUE_SIZE],
    // Turns taken, for SHARED_QUEUE_INTERVAL
    turns : u64,
    // For choosing which carrier to take from
    random : u64,
    // The waiter of the fiber that's parking, from park_fiber until its switch back is done
    parking : ptr[mut runtime.Waiter]?,
}

create_fiber_pool :: fn(allocator := context.allocator) -> ptr[mut FiberPool] {
    pool :: runtime.new(FiberPool, allocator)
    pool.scheduler.wake_function = requeue_fiber
    pool.lock = concurrency.SpinLock.{}
    pool.first = null
    pool.last = null
    pool.shared_count = 0
    pool.live = 0
    pool.closed = 0
    pool.carrier_count = 0
    pool.active_carriers = 0
    pool.work_epoch = 0
    pool.sleepers = 0
    pool.allocator = allocator
    return pool
}

/*
 * Free the pool, once it's closed and every carrier has left run_carrier. Fibers that never ran
 * are freed too.
 */
destroy_fiber_pool :: fn(pool: ptr[mut FiberPool]) {
    allocator :: pool.allocator
    count :: intrinsics.atomic_load_u64_acquire(&pool.carrier_count)
    for i in 0..<count {
        if i < MAX_CARRIERS {
            runtime.free(cast[ptr[PoolCarrier]](pool.carriers[i]), allocator)
        }
    }
    loop {
        fiber :: pool.first or_break
        pool.first = fiber.next
        runtime.fiber_destroy(fiber, allocator)
    }
    runtime.free(pool, allocator)
}

/*
 * Make a fiber that will run function(data), and queue it: on this carrier, if this is one of
 * the pool's fibers, otherwise in the shared queue.
 */
spawn :: fn(
    pool #escaping : ptr[mut FiberPool],
    function: runtime.ThreadFunction,
    data #escaping : any? = null,
) -> (ptr[mut runtime.Fiber]?, runtime.AllocatorError?) {
    made, error :: runtime.fiber_create(function, data, pool.allocator)
    match made {
        case Some(fiber) => {
            fiber.scheduler = &pool.scheduler
            intrinsics.interlocked_exchange_add_u64(&pool.live, 1)
            match carrier_in(pool) {
                case Some(here) => add_local(here, fiber)
                case None => add_shared(pool, fiber, fiber, 1)
            }
            return fiber, null
        }
        case None => return null, error
    }
}

/*
 * No more fibers come from outside the pool: once every fiber has finished, carriers leave
 * run_carrier. Fibers can still spawn more.
 */
close_pool :: fn(pool: ptr[mut FiberPool]) {
    intrinsics.atomic_store_u64_release(&pool.closed, 1)
    wake_carriers(pool, true)
}

/*
 * Run the pool's fibers on this thread, with the other carriers running it, until the pool is
 * closed and every fiber has finished. Called from a plain thread, not from a fiber, and not
 * while this thread runs another pool.
 */
run_carrier :: fn(pool #escaping : ptr[mut FiberPool]) {
    {
        carrier :: intrinsics.carrier()
        if carrier.current_fiber != null || carrier.yield_function != null {
            runtime.log_error("run_carrier is being called from a fiber, or a thread already running a pool")
            return void
        }
    }
    here :: runtime.new(PoolCarrier, pool.allocator)
    here.pool = pool
    here.head = 0
    here.tail = 0
    here.turns = 0
    here.parking = null
    {
        concurrency.lock(&pool.lock)
        defer concurrency.unlock(&pool.lock)
        index :: pool.carrier_count
        if index >= MAX_CARRIERS {
            runtime.log_error("a fiber pool can have at most % carriers", MAX_CARRIERS)
            runtime.free(here, pool.allocator)
            return void
        }
        pool.carriers[index] = cast[rawptr](here)
        intrinsics.atomic_store_u64_release(&pool.carrier_count, index + 1)
        // Different carriers start their searches in different places
        here.random = (index + 1) * 0x9e3779b97f4a7c15
    }
    intrinsics.interlocked_exchange_add_u64(&pool.active_carriers, 1)

    /*
     * The loop itself never yields (it isn't running on a fiber), so the carrier stays the same
     * and this pointer stays valid.
     */
    carrier :: intrinsics.carrier()
    carrier.yield_function = yield
    carrier.park_function = park_fiber
    carrier.scheduler_data = cast[rawptr](here)
    defer {
        carrier.yield_function = null
        carrier.park_function = null
        carrier.scheduler_data = null
    }
    idle := 0
    loop {
        /*
         * The epoch is read before looking for work: anything added after that changes it, so the
         * wait below returns at once instead of missing it.
         */
        epoch :: intrinsics.atomic_load_u32_acquire(&pool.work_epoch)
        match next_fiber(here) {
            case Some(fiber) => {
                idle = 0
                run_turn(here, fiber)
            }
            case None => {
                if intrinsics.atomic_load_u64_acquire(&pool.closed) != 0 && intrinsics.atomic_load_u64_acquire(&pool.live) == 0 {
                    break
                }
                idle += 1
                if idle < IDLE_SPINS {
                    intrinsics.spin_hint()
                }
                else {
                    intrinsics.interlocked_increment_u64(&pool.sleepers)
                    runtime.wait_on_value(&pool.work_epoch, epoch)
                    intrinsics.interlocked_decrement_u64(&pool.sleepers)
                }
            }
        }
    }
    intrinsics.interlocked_decrement_u64(&pool.active_carriers)
}

/*
 * A turn for a fiber: started or resumed here, until it yields, when it goes to the back of the
 * shared queue, or finishes, when it's freed.
 */
run_turn :: fn(here: ptr[mut PoolCarrier], fiber #escaping : ptr[mut runtime.Fiber]) {
    pool :: here.pool
    exit := runtime.FiberExit.Finished
    if fiber.state == .NotStarted {
        exit = intrinsics.fiber_start(fiber)
    }
    else {
        exit = intrinsics.fiber_resume(fiber)
    }
    /*
     * Only now, with the fiber switched away from, can another carrier take it: queued any
     * sooner, it could be resumed while still running here.
     */
    if exit == .Yielded {
        match here.parking {
            case Some(waiter) => {
                /*
                 * Parked, unless it was woken while it switched away, in which case it goes
                 * straight back in the queue. Once it's marked parked, whoever wakes it queues it.
                 */
                here.parking = null
                _, parked :: intrinsics.interlocked_compare_exchange_u32(&waiter.state, runtime.WAITER_PARKED, runtime.WAITER_WAITING)
                if !parked {
                    add_shared(pool, fiber, fiber, 1)
                }
            }
            case None => add_shared(pool, fiber, fiber, 1)
        }
    }
    else {
        runtime.fiber_destroy(fiber, pool.allocator)
        // The last one (it gives the count from before): carriers asleep can leave, if the pool is closed
        if intrinsics.interlocked_decrement_u64(&pool.live) == 1 {
            wake_carriers(pool, true)
        }
    }
}

/*
 * Tell sleeping carriers there's something to look at: one, for new work, or all of them. The
 * epoch changes first, and both are full fences, so a carrier that read the old epoch and hasn't
 * counted itself as a sleeper yet won't sleep through it: its wait finds the epoch changed.
 */
wake_carriers :: fn(pool: ptr[mut FiberPool], all: bool) {
    intrinsics.interlocked_increment_u32(&pool.work_epoch)
    if intrinsics.atomic_load_u64(&pool.sleepers) == 0 {
        return void
    }
    if all {
        runtime.wake_all(&pool.work_epoch)
    }
    else {
        runtime.wake_one(&pool.work_epoch)
    }
}

/*
 * Installed as the carrier's yield_function, so it's what fiber_yield calls on one of the pool's
 * fibers, on the fiber's own stack. fiber_yield has already checked foreign_depth and
 * no_yield_depth.
 */
yield :: fn(carrier: ptr[mut runtime.CarrierBlock]) {
    current :: carrier.current_fiber or_return void
    here :: cast[ptr[mut PoolCarrier]](carrier.scheduler_data)
    // With nothing else waiting here or in the shared queue, switching would be pointless
    if intrinsics.atomic_load_u64_acquire(&here.tail) == intrinsics.atomic_load_u64_acquire(&here.head)
        && intrinsics.atomic_load_u64_acquire(&here.pool.shared_count) == 0 {
        return void
    }
    /*
     * Back to the carrier's loop, which queues this fiber. Only "returns" once the fiber is
     * resumed, possibly on another carrier, so don't use carrier or here after this.
     */
    intrinsics.fiber_suspend(current)
}

/*
 * Installed as the carrier's park_function, so it's what runtime.park calls on one of the pool's
 * fibers, on the fiber's own stack: back to the carrier's loop, which marks the waiter parked
 * (run_turn). Only "returns" once woken, possibly on another carrier.
 */
park_fiber :: fn(carrier: ptr[mut runtime.CarrierBlock], waiter #escaping : ptr[mut runtime.Waiter]) {
    current :: carrier.current_fiber or_return void
    here :: cast[ptr[mut PoolCarrier]](carrier.scheduler_data)
    here.parking = waiter
    intrinsics.fiber_suspend(current)
}

// The pool's wake_function: back in its shared queue, from whichever thread woke the fiber.
requeue_fiber :: fn(fiber #escaping : ptr[mut runtime.Fiber]) {
    scheduler :: fiber.scheduler or_return void
    // The scheduler is the pool's first field
    pool :: cast[ptr[mut FiberPool]](scheduler)
    add_shared(pool, fiber, fiber, 1)
}

// This carrier's part of pool, if it's running one of the pool's fibers.
carrier_in :: fn(pool: ptr[FiberPool]) -> ptr[mut PoolCarrier]? {
    carrier :: intrinsics.carrier()
    if carrier.current_fiber == null {
        return null
    }
    installed :: carrier.yield_function or_return null
    if installed != yield {
        return null
    }
    here :: cast[ptr[mut PoolCarrier]](carrier.scheduler_data)
    if cast[rawptr](here.pool) != cast[rawptr](pool) {
        return null
    }
    return here
}

// The next fiber for this carrier to run, from its own queue, the shared queue, or another carrier's.
next_fiber :: fn(here: ptr[mut PoolCarrier]) -> ptr[mut runtime.Fiber]? {
    here.turns += 1
    if here.turns % SHARED_QUEUE_INTERVAL == 0 {
        match take_shared(here) {
            case Some(fiber) => return fiber
            case None => {}
        }
    }
    match take_local(here) {
        case Some(fiber) => return fiber
        case None => {}
    }
    match take_shared(here) {
        case Some(fiber) => return fiber
        case None => {}
    }
    return steal_any(here)
}

// ---------------------------------------------------------------------------------------------
// The carrier's own queue

// Add to the back of this carrier's queue, moving half of it to the shared queue if it's full.
add_local :: fn(here: ptr[mut PoolCarrier], fiber #escaping : ptr[mut runtime.Fiber]) {
    loop {
        head :: intrinsics.atomic_load_u64_acquire(&here.head)
        // Only this carrier changes tail
        tail :: here.tail
        if tail - head < LOCAL_QUEUE_SIZE {
            here.queue[tail & LOCAL_QUEUE_MASK] = cast[rawptr](fiber)
            intrinsics.atomic_store_u64_release(&here.tail, tail + 1)
            // Another carrier may be asleep with nothing to take
            wake_carriers(here.pool, false)
            return void
        }
        if move_half_to_shared(here, head, fiber) {
            return void
        }
    }
}

/*
 * The full queue's first half, then fiber, to the back of the shared queue. False if another
 * carrier took some of the queue first, so it isn't full anymore.
 */
move_half_to_shared :: fn(here: ptr[mut PoolCarrier], head: u64, fiber #escaping : ptr[mut runtime.Fiber]) -> bool {
    half :: cast[u64](LOCAL_QUEUE_SIZE / 2)
    // Linked first, and only queued once they're taken
    first :: cast[ptr[mut runtime.Fiber]](here.queue[head & LOCAL_QUEUE_MASK])
    previous := first
    for i in 1..<half {
        next :: cast[ptr[mut runtime.Fiber]](here.queue[(head + i) & LOCAL_QUEUE_MASK])
        previous.next = next
        previous = next
    }
    _, taken :: intrinsics.interlocked_compare_exchange_u64(&here.head, head + half, head)
    if !taken {
        return false
    }
    previous.next = fiber
    add_shared(here.pool, first, fiber, half + 1)
    return true
}

// The fiber at a position in this carrier's queue.
fiber_at :: fn(here: ptr[PoolCarrier], position: u64) -> ptr[mut runtime.Fiber] {
    return cast[ptr[mut runtime.Fiber]](here.queue[position & LOCAL_QUEUE_MASK])
}

// Take from the front of this carrier's queue.
take_local :: fn(here: ptr[mut PoolCarrier]) -> ptr[mut runtime.Fiber]? {
    loop {
        head :: intrinsics.atomic_load_u64_acquire(&here.head)
        if head == here.tail {
            return null
        }
        fiber :: fiber_at(here, head)
        _, taken :: intrinsics.interlocked_compare_exchange_u64(&here.head, head + 1, head)
        if taken {
            return fiber
        }
    }
}

/*
 * Take half of another carrier's queue, starting with a different carrier each time: the first
 * fiber to run now, the rest into this carrier's queue, which is empty.
 */
steal_any :: fn(here: ptr[mut PoolCarrier]) -> ptr[mut runtime.Fiber]? {
    pool :: here.pool
    count :: intrinsics.atomic_load_u64_acquire(&pool.carrier_count)
    if count < 2 {
        return null
    }
    // xorshift
    here.random ~= here.random << 13
    here.random ~= here.random >> 7
    here.random ~= here.random << 17
    start :: here.random % count
    for i in 0..<count {
        index :: (start + i) % count
        if index < MAX_CARRIERS && pool.carriers[index] != cast[rawptr](here) {
            match steal_from(here, cast[ptr[mut PoolCarrier]](pool.carriers[index])) {
                case Some(fiber) => return fiber
                case None => {}
            }
        }
    }
    return null
}

steal_from :: fn(here: ptr[mut PoolCarrier], other: ptr[mut PoolCarrier]) -> ptr[mut runtime.Fiber]? {
    tail :: here.tail
    loop {
        head :: intrinsics.atomic_load_u64_acquire(&other.head)
        other_tail :: intrinsics.atomic_load_u64_acquire(&other.tail)
        if other_tail <= head {
            return null
        }
        waiting :: other_tail - head
        // Read while its owner kept changing it: try again
        if waiting > LOCAL_QUEUE_SIZE {
            continue
        }
        count :: waiting - waiting / 2
        // Copied before they're taken, since once they are, the other carrier may reuse their slots
        for i in 0..<count {
            here.queue[(tail + i) & LOCAL_QUEUE_MASK] = other.queue[(head + i) & LOCAL_QUEUE_MASK]
        }
        _, taken :: intrinsics.interlocked_compare_exchange_u64(&other.head, head + count, head)
        if taken {
            // The last one runs now, the others are this carrier's
            intrinsics.atomic_store_u64_release(&here.tail, tail + count - 1)
            return fiber_at(here, tail + count - 1)
        }
    }
}

// ---------------------------------------------------------------------------------------------
// The shared queue

// Add a chain of fibers, first to last, linked through next, to the back of the shared queue.
add_shared :: fn(pool: ptr[mut FiberPool], first #escaping : ptr[mut runtime.Fiber], last #escaping : ptr[mut runtime.Fiber],
    count: u64) {

    last.next = null
    {
        concurrency.lock(&pool.lock)
        defer concurrency.unlock(&pool.lock)
        match pool.last {
            case Some(previous) => previous.next = first
            case None => pool.first = first
        }
        pool.last = last
        intrinsics.atomic_store_u64_release(&pool.shared_count, pool.shared_count + count)
    }
    wake_carriers(pool, false)
}

/*
 * Take from the front of the shared queue: the first fiber to run now, and this carrier's share
 * of the rest (the queue divided among the carriers running) into its own queue, as far as half
 * of it has room.
 */
take_shared :: fn(here: ptr[mut PoolCarrier]) -> ptr[mut runtime.Fiber]? {
    pool :: here.pool
    if intrinsics.atomic_load_u64_acquire(&pool.shared_count) == 0 {
        return null
    }
    concurrency.lock(&pool.lock)
    defer concurrency.unlock(&pool.lock)
    result :: pool.first or_return null
    remaining :: pool.shared_count - 1
    carriers :: intrinsics.atomic_load_u64_acquire(&pool.active_carriers)
    head :: intrinsics.atomic_load_u64_acquire(&here.head)
    tail :: here.tail
    half :: cast[u64](LOCAL_QUEUE_SIZE / 2)
    room :: half - min_of(tail - head, half)
    share :: min_of(remaining / (if carriers == 0 { cast[u64](1) } else { carriers }), room)
    walk := result.next
    for i in 0..<share {
        fiber :: walk or_break
        here.queue[(tail + i) & LOCAL_QUEUE_MASK] = cast[rawptr](fiber)
        walk = fiber.next
    }
    pool.first = walk
    if walk == null {
        pool.last = null
    }
    intrinsics.atomic_store_u64_release(&pool.shared_count, remaining - share)
    intrinsics.atomic_store_u64_release(&here.tail, tail + share)
    result.next = null
    return result
}

min_of :: fn(a, b: u64) -> u64 {
    return if a < b { a } else { b }
}
