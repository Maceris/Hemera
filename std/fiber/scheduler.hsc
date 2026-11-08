package fiber

import intrinsics from "base"
import runtime from "base"
import concurrency from "std"

/**
 * A pool of fibers that one or more carriers share (docs/multitasking.md, Fiber Pools).
 *
 * Each thread chooses whether to run a pool: a program can have threads without one, and any number of pools, each run
 * by its own set of threads.
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
    /**
     * What the pool's fibers point to, for runtime.wake. It's first, so a fiber's scheduler is its pool, at the same
     * address.
     */
    scheduler : runtime.FiberScheduler,
    /** Guards the shared queue, and the list of carriers while one joins. */
    lock : concurrency.SpinLock,
    /** The front of the shared queue, linked through Fiber.next, first to run first; null when it's empty. */
    first : ptr[mut runtime.Fiber]?,
    /** The back of the shared queue, where fibers are added; null when it's empty. */
    last : ptr[mut runtime.Fiber]?,
    /** How many fibers are in the shared queue: written under the lock, read without it. */
    shared_count : u64,
    /** Fibers spawned that haven't finished, parked and suspended ones included. Changed atomically. */
    live : u64,
    /** Nonzero once close_pool was called: once no fiber is live, carriers leave. A u64 so it's read atomically. */
    closed : u64,
    /**
     * Every carrier that has joined, as ptr[mut PoolCarrier], kept until the pool is destroyed: carrier_count of them.
     */
    carriers : rawptr[MAX_CARRIERS],
    /** How many of carriers are filled in, up to MAX_CARRIERS; carriers that left still count. */
    carrier_count : u64,
    /** Carriers in run_carrier now, which the shared queue is divided among. */
    active_carriers : u64,
    /** Changes whenever there's something for a sleeping carrier to look at, which it sleeps on. Wraps around. */
    work_epoch : u32,
    /** Carriers asleep, or about to be, so adding work only wakes one when there is one. */
    sleepers : u64,
    /**
     * Where the pool, its carriers' parts and its fibers come from. Carriers use it at the same time, so it has to be
     * safe for that.
     */
    allocator : runtime.Allocator,
}

/** The most carriers one pool can have; a thread joining past it logs an error and leaves run_carrier at once. */
MAX_CARRIERS :: 64
/** How many fibers a carrier's own queue holds: a power of two, so a position masked is its slot. */
LOCAL_QUEUE_SIZE :: 256
/** A position in a carrier's queue masked with this is its slot. */
LOCAL_QUEUE_MASK :: LOCAL_QUEUE_SIZE - 1
/**
 * Every this many turns, a carrier looks at the shared queue first, so it isn't left waiting. Prime, so it doesn't
 * fall into step with other periodic work.
 */
SHARED_QUEUE_INTERVAL :: 61
/** How many times a carrier with nothing to run looks again before it sleeps. */
IDLE_SPINS :: 64

/**
 * One carrier's part of a pool, the carrier block's scheduler_data while it runs the pool.
 *
 * It's kept until the pool is destroyed, since other carriers may be looking at its queue. The carrier's own queue is
 * a ring: the carrier adds at tail and takes at head, and other carriers take at head too, so head only moves by
 * compare and exchange. Neither wraps, being 64 bits.
 */
PoolCarrier :: struct {
    /** The pool it's part of. */
    pool : ptr[mut FiberPool],
    /**
     * The position of the queue's front, which this carrier and others take from; moved only by compare and exchange.
     */
    head : u64,
    /** The position past the queue's back, which only this carrier changes. tail - head fibers are queued. */
    tail : u64,
    /** The queue's slots, each a ptr[mut runtime.Fiber], at positions masked with LOCAL_QUEUE_MASK. */
    queue : rawptr[LOCAL_QUEUE_SIZE],
    /** Turns taken, for SHARED_QUEUE_INTERVAL. */
    turns : u64,
    /** The state of an xorshift generator, for choosing which carrier to take from; never 0. */
    random : u64,
    /** The waiter of the fiber that's parking, from park_fiber until its switch back is done; null otherwise. */
    parking : ptr[mut runtime.Waiter]?,
}

/**
 * Make a fiber pool, open and with no carriers or fibers.
 *
 * @param allocator Where the pool, its carriers' parts and its fibers come from. Carriers allocate and free with it at
 *     the same time, so it has to be safe for several threads; it must outlive the pool.
 * @return The pool, owned by the caller, who frees it with destroy_fiber_pool. Never null: if it can't be allocated,
 *     context.assertion_handler is called, as runtime.new does.
 */
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

/**
 * Free the pool, with its carriers' parts and any fibers still in its shared queue, which never ran.
 *
 * @param pool The pool, which must be closed, with every carrier gone from run_carrier: nothing checks this, and a
 *     carrier still running would use freed memory. It, and every fiber pointer from spawn, is invalid afterwards.
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

/**
 * Make a fiber that will run function(data), and queue it.
 *
 * It's queued on this carrier, if this is one of the pool's fibers, otherwise in the shared queue, and a sleeping
 * carrier is woken to run it. It starts with a copy of the caller's context. Any thread may spawn, and a closed pool
 * still takes fibers, though once its last fiber has finished no carrier may be left to run them.
 *
 * @param pool The pool, which must outlive the fiber.
 * @param function What the fiber runs.
 * @param data What function is given, or null for an empty any. It's kept until the fiber runs, maybe on another
 *     thread, so it can't point into the caller's stack.
 * @return The fiber, owned by the pool, which frees it when it finishes: valid only until then, so mostly for
 *     identifying it. Null on an error.
 * @return The allocator's error when the fiber couldn't be made, with nothing queued; null on success.
 */
spawn :: fn(
    pool #escaping : ptr[mut FiberPool],
    function: runtime.ThreadFunction,
    data #escaping #crosses_threads : any? = null,
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

/**
 * Close the pool: once every fiber has finished, carriers leave run_carrier.
 *
 * Fibers can still spawn more, so carriers stay while any is live. Closing wakes every sleeping carrier, so ones with
 * nothing left to run see it. Closing twice does no harm.
 *
 * @param pool The pool, from any thread.
 */
close_pool :: fn(pool: ptr[mut FiberPool]) {
    intrinsics.atomic_store_u64_release(&pool.closed, 1)
    wake_carriers(pool, true)
}

/**
 * Run the pool's fibers on this thread, with the other carriers running it, until the pool is closed and every fiber
 * has finished.
 *
 * It's called from a plain thread, not from a fiber, and not while this thread runs another pool; either is logged as
 * an error, and it returns at once. So does a carrier past MAX_CARRIERS. While it runs, the thread's carrier block
 * has the pool's yield and park functions installed, and they're taken out again when it returns.
 *
 * @param pool The pool, which must outlive the call. This carrier's part of it is allocated with the pool's
 *     allocator, and kept until the pool is destroyed; if it can't be allocated, context.assertion_handler is called.
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
                    runtime.deterministic_turn()
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

/**
 * Give a fiber a turn: start or resume it here until it yields, parks or finishes.
 *
 * A fiber that yields goes to the back of the shared queue; one that parks is left out of the queues until woken,
 * unless it was woken while it switched away; one that finishes is freed, and the last to finish wakes every carrier.
 *
 * @param here This carrier's part of the pool.
 * @param fiber The fiber, NotStarted or Suspended, taken off a queue.
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

/**
 * Tell sleeping carriers there's something to look at.
 *
 * The epoch changes first, and both are full fences, so a carrier that read the old epoch and hasn't counted itself as
 * a sleeper yet won't sleep through it: its wait finds the epoch changed.
 *
 * @param pool The pool, from any thread.
 * @param all True to wake every sleeping carrier, for a pool that's closing or whose last fiber finished; false to wake
 *     one, for new work.
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

/**
 * Let other fibers run: installed as the carrier's yield_function, so it's what fiber_yield calls on one of the pool's
 * fibers, on the fiber's own stack.
 *
 * fiber_yield has already checked foreign_depth and no_yield_depth. With nothing else queued here or in the shared
 * queue, it returns at once without switching.
 *
 * @param carrier The carrier block of the thread the fiber is on. It, and the carrier's part of the pool, may belong
 *     to another thread once the fiber is resumed.
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

/**
 * Suspend a fiber until it's woken: installed as the carrier's park_function, so it's what runtime.park calls on one
 * of the pool's fibers, on the fiber's own stack.
 *
 * It switches back to the carrier's loop, which marks the waiter parked (run_turn). It only "returns" once woken,
 * possibly on another carrier.
 *
 * @param carrier The carrier block of the thread the fiber is on.
 * @param waiter The fiber's waiter, which runtime.wake uses to put it back in the queue.
 */
park_fiber :: fn(carrier: ptr[mut runtime.CarrierBlock], waiter #escaping : ptr[mut runtime.Waiter]) {
    current :: carrier.current_fiber or_return void
    here :: cast[ptr[mut PoolCarrier]](carrier.scheduler_data)
    here.parking = waiter
    intrinsics.fiber_suspend(current)
}

/**
 * Put a woken fiber back in its pool's shared queue: the pool's wake_function, from whichever thread woke it.
 *
 * @param fiber The parked fiber. One without a scheduler is left alone.
 */
requeue_fiber :: fn(fiber #escaping : ptr[mut runtime.Fiber]) {
    scheduler :: fiber.scheduler or_return void
    // The scheduler is the pool's first field
    pool :: cast[ptr[mut FiberPool]](scheduler)
    add_shared(pool, fiber, fiber, 1)
}

/**
 * Find this carrier's part of a pool, if this thread is running one of the pool's fibers.
 *
 * @param pool A pool from create_fiber_pool, not yet destroyed; only read.
 * @return This carrier's part of pool; null when called outside a fiber, from a fiber of another scheduler, or from
 *     one of another pool's fibers.
 */
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

/**
 * Take the next fiber for this carrier to run, from its own queue, the shared queue, or another carrier's.
 *
 * Every SHARED_QUEUE_INTERVAL turns the shared queue comes first, so it isn't left waiting behind a busy local queue.
 *
 * @param here This carrier's part of the pool.
 * @return The fiber, taken off its queue; null if there's nothing to run anywhere.
 */
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

/**
 * Add a fiber to the back of this carrier's queue, moving half of the queue to the shared queue if it's full.
 *
 * A sleeping carrier is woken, so it can take some of the work.
 *
 * @param here This carrier's part of the pool; only its own carrier adds to it.
 * @param fiber The fiber, ready to run.
 */
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

/**
 * Move a full queue's first half, then a fiber, to the back of the shared queue.
 *
 * @param here This carrier's part of the pool, whose queue is full.
 * @param head The queue's head when it was seen full.
 * @param fiber The fiber that didn't fit, queued after the half.
 * @return True if they were moved; false if another carrier took some of the queue first, so it isn't full anymore
 *     and nothing was moved.
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

/**
 * Read the fiber at a position in a carrier's queue.
 *
 * @param here The carrier's part of the pool.
 * @param position A position in the queue, between head and tail; it's masked to its slot.
 * @return The fiber in that slot.
 */
fiber_at :: fn(here: ptr[PoolCarrier], position: u64) -> ptr[mut runtime.Fiber] {
    return cast[ptr[mut runtime.Fiber]](here.queue[position & LOCAL_QUEUE_MASK])
}

/**
 * Take a fiber from the front of this carrier's queue, racing other carriers stealing from it.
 *
 * @param here This carrier's part of the pool.
 * @return The fiber; null if the queue is empty.
 */
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

/**
 * Take half of another carrier's queue, starting with a different carrier each time.
 *
 * @param here This carrier's part of the pool, whose queue is empty.
 * @return A fiber to run now, the rest taken going into this carrier's queue; null if every other carrier's queue is
 *     empty, or this is the pool's only carrier.
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

/**
 * Take half of one other carrier's queue, rounded up.
 *
 * @param here This carrier's part of the pool, whose queue is empty.
 * @param other The carrier to take from.
 * @return The last fiber taken, to run now, the others going into this carrier's queue; null if other's queue is
 *     empty.
 */
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

/**
 * Add a chain of fibers to the back of the shared queue, and wake a sleeping carrier for them.
 *
 * @param pool The pool, from any thread.
 * @param first The chain's first fiber, linked to the others through next.
 * @param last The chain's last fiber, whose next is set to null; first itself for a chain of one.
 * @param count How many fibers are in the chain, at least 1.
 */
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

/**
 * Take fibers from the front of the shared queue.
 *
 * @param here This carrier's part of the pool.
 * @return The first fiber, to run now, with this carrier's share of the rest (the queue divided among the carriers
 *     running) moved into its own queue, as far as half of it has room; null if the shared queue is empty.
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

/**
 * Pick the smaller of two counts.
 *
 * @param a A count, in any unit, as long as b's is the same.
 * @param b The count compared with a, in a's unit.
 * @return Whichever is smaller; either when they're equal.
 */
min_of :: fn(a, b: u64) -> u64 {
    return if a < b { a } else { b }
}
