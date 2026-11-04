package runtime

import intrinsics from "base"

/**
 * Waiting for something another fiber or thread does, like a lock being released
 * (docs/multitasking.md, Waiting). Every fiber and every thread has one Waiter, in its Fiber or
 * its carrier block, since it waits for one thing at a time:
 *
 *     waiter :: current_waiter()
 *     prepare_wait(waiter)
 *     // put waiter on the thing's list of waiters, under its lock
 *     park(waiter)            // returns once wake(waiter) has been called
 *
 * and whoever finishes the thing takes the waiter off the list and calls wake(waiter). The wake
 * can come before park, or while the fiber is still switching away: it's never lost.
 */
Waiter :: struct {
    /**
     * WAITER_IDLE, WAITER_WAITING, WAITER_PARKED or WAITER_WOKEN, changed atomically. A u32, not an enum, since a
     * blocked thread sleeps on it with wait_on_value.
     */
    state : u32,
    /** 1 for a fiber's waiter, the one in its Fiber, and 0 for a thread's; set by current_waiter. */
    on_fiber : u32,
    /**
     * For whatever it's waiting on to keep a list of its waiters, under that thing's own lock; null at the list's end,
     * and cleared by prepare_wait.
     */
    next : ptr[mut Waiter]?,
}

/** Not waiting. */
WAITER_IDLE : u32 : 0
/** About to wait: on a list, but not suspended yet, or a thread waiting on state. */
WAITER_WAITING : u32 : 1
/** A suspended fiber, which whoever wakes it queues again. */
WAITER_PARKED : u32 : 2
/** Woken: park returns. */
WAITER_WOKEN : u32 : 3

/**
 * Fetch the waiter for what's running now: the current fiber's, or the thread's when it isn't running a fiber.
 *
 * Marks the waiter as a fiber's or a thread's, so wake knows how to wake it.
 *
 * @return The waiter, in the Fiber or the carrier block, never null. It stays valid as long as the fiber or thread
 *     does, but it belongs to whatever's running now: a fiber's moves with the fiber to other carriers.
 */
current_waiter :: fn() -> ptr[mut Waiter] {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    match carrier.current_fiber {
        case Some(fiber) => {
            fiber.waiter.on_fiber = 1
            return &fiber.waiter
        }
        case None => {
            carrier.thread_waiter.on_fiber = 0
            return &carrier.thread_waiter
        }
    }
}

/**
 * Ready a waiter to be put on a list, before anything can wake it.
 *
 * @param waiter The waiter, from current_waiter, which isn't on any list yet: its link is cleared, and its state set
 *     to WAITER_WAITING with release ordering, so a wake from then on isn't lost.
 */
prepare_wait :: fn(waiter: ptr[mut Waiter]) {
    waiter.next = null
    intrinsics.atomic_store_u32_release(&waiter.state, WAITER_WAITING)
}

/**
 * Wait until wake(waiter).
 *
 * A fiber run by a scheduler with a park_function is suspended, and its carrier runs other fibers; it may come back
 * on another carrier. Anywhere else (a plain thread, or a fiber with foreign frames on its stack or inside a no-yield
 * region) the thread blocks, with wait_on_value. A wake that came before park makes it return at once.
 *
 * @param waiter The caller's own waiter, from current_waiter, readied by prepare_wait. Whoever wakes it may hold it
 *     until then, so it has to stay valid until park returns.
 */
park :: fn(waiter #escaping : ptr[mut Waiter]) {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    if carrier.current_fiber != null && carrier.foreign_depth == 0 && carrier.no_yield_depth == 0 {
        match carrier.park_function {
            case Some(suspend) => {
                /*
                 * Comes back once woken, possibly on another carrier, so don't use carrier after
                 * this.
                 */
                suspend(carrier, waiter)
                return void
            }
            case None => {}
        }
    }
    loop {
        state :: intrinsics.atomic_load_u32_acquire(&waiter.state)
        if state == WAITER_WOKEN {
            break
        }
        wait_on_value(&waiter.state, state)
    }
}

/**
 * Wake a waiter, from any thread: a parked fiber goes back to its scheduler's queue, through the
 * scheduler's wake_function, and a thread returns from park.
 *
 * @param waiter The waiter, taken off whatever list it was on. Its state becomes WAITER_WOKEN; a waiter that hasn't
 *     parked yet returns from park at once when it does. Once woken, its owner may reuse it for its next wait, so the
 *     caller mustn't touch it after this. A parked fiber's waiter whose fiber has no scheduler is only marked woken.
 */
wake :: fn(waiter: ptr[mut Waiter]) {
    // Read first: once woken, a thread's waiter may be used for its next wait at once
    on_fiber :: waiter.on_fiber
    old :: intrinsics.interlocked_exchange_u32(&waiter.state, WAITER_WOKEN)
    if old == WAITER_PARKED && on_fiber != 0 {
        // The fiber it's part of
        parked :: cast[ptr[mut Fiber]](cast[rawptr](cast[usize](waiter) - offset_of(Fiber, waiter)))
        scheduler :: parked.scheduler or_return void
        scheduler.wake_function(parked)
        return void
    }
    // A thread, or a fiber that blocked its thread, may be asleep on the state
    if old == WAITER_WAITING {
        wake_one(&waiter.state)
    }
}
