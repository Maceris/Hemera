package concurrency

import runtime from "base"

/*
 * A lock that waits without spinning: a fiber that has to wait parks, so its carrier runs other
 * fibers meanwhile, and a thread blocks (runtime.park). Waiters are served in order, and unlocking
 * hands the lock straight to the first of them, so nobody waits forever.
 *
 *     mutex_lock(&mutex)
 *     defer mutex_unlock(&mutex)
 *
 * A fiber holding it may yield or park; others wanting it wait meanwhile.
 */
Mutex :: struct {
    // Guards the rest, for a few instructions at a time
    guard : SpinLock,
    locked : bool,
    // Waiting for it, first to get it first, linked through Waiter.next
    first : ptr[mut runtime.Waiter]?,
    last : ptr[mut runtime.Waiter]?,
}

mutex_lock :: fn(mutex: ptr[mut Mutex]) {
    lock(&mutex.guard)
    if !mutex.locked {
        mutex.locked = true
        unlock(&mutex.guard)
        return void
    }
    waiter :: runtime.current_waiter()
    runtime.prepare_wait(waiter)
    match mutex.last {
        case Some(previous) => previous.next = waiter
        case None => mutex.first = waiter
    }
    mutex.last = waiter
    unlock(&mutex.guard)
    // Comes back holding it: mutex_unlock handed it over
    runtime.park(waiter)
}

mutex_unlock :: fn(mutex: ptr[mut Mutex]) {
    lock(&mutex.guard)
    next :: mutex.first
    match next {
        case Some(waiter) => {
            // Still locked, now the waiter's
            mutex.first = waiter.next
            if mutex.first == null {
                mutex.last = null
            }
        }
        case None => mutex.locked = false
    }
    unlock(&mutex.guard)
    match next {
        case Some(waiter) => runtime.wake(waiter)
        case None => {}
    }
}
