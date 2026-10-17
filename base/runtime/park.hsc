package runtime

import intrinsics from "base"

/*
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
    // WAITER_IDLE, WAITER_WAITING, WAITER_PARKED or WAITER_WOKEN
    state : u64,
    // The fiber waiting, or null for a thread
    fiber : ptr[mut Fiber]?,
    // For whatever it's waiting on to keep a list of its waiters
    next : ptr[mut Waiter]?,
}

// Not waiting.
WAITER_IDLE : u64 : 0
// About to wait: on a list, but not suspended yet, or a thread waiting on state.
WAITER_WAITING : u64 : 1
// A suspended fiber, which whoever wakes it queues again.
WAITER_PARKED : u64 : 2
// Woken: park returns.
WAITER_WOKEN : u64 : 3

// The current fiber's waiter, or the thread's when it isn't running a fiber.
current_waiter :: fn() -> ptr[mut Waiter] {
    carrier : ptr[mut CarrierBlock] : intrinsics.carrier()
    match carrier.current_fiber {
        case Some(fiber) => {
            fiber.waiter.fiber = fiber
            return &fiber.waiter
        }
        case None => {
            carrier.thread_waiter.fiber = null
            return &carrier.thread_waiter
        }
    }
}

// Ready a waiter to be put on a list, before anything can wake it.
prepare_wait :: fn(waiter: ptr[mut Waiter]) {
    waiter.next = null
    intrinsics.atomic_store_u64_release(&waiter.state, WAITER_WAITING)
}

/*
 * Wait until wake(waiter). A fiber run by a scheduler with a park_function is suspended, and its
 * carrier runs other fibers; anywhere else (a plain thread, or a fiber with foreign frames on its
 * stack or inside a no-yield region) the thread blocks, with wait_on_value.
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
        state :: intrinsics.atomic_load_u64_acquire(&waiter.state)
        if state == WAITER_WOKEN {
            break
        }
        wait_on_value(&waiter.state, state)
    }
}

/*
 * Wake a waiter, from any thread: a parked fiber goes back to its scheduler's queue, through its
 * wake_function, and a thread returns from park.
 */
wake :: fn(waiter: ptr[mut Waiter]) {
    // Read first: once woken, a thread's waiter may be used for its next wait at once
    fiber :: waiter.fiber
    old :: intrinsics.interlocked_exchange_u64(&waiter.state, WAITER_WOKEN)
    if old == WAITER_PARKED {
        parked :: fiber or_return void
        requeue :: parked.wake_function or_return void
        requeue(parked)
        return void
    }
    // A thread, or a fiber that blocked its thread, may be asleep on the state
    if old == WAITER_WAITING {
        wake_one(&waiter.state)
    }
}
