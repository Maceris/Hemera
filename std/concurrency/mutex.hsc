package concurrency

import runtime from "base"

/**
 * A lock that waits without spinning.
 *
 * A fiber that has to wait parks, so its carrier runs other fibers meanwhile, and a thread blocks (runtime.park).
 * Waiters are served in order, and unlocking hands the lock straight to the first of them, so nobody waits forever.
 * Its zero value is unlocked. It isn't reentrant: a holder that locks it again waits forever.
 *
 *     mutex_lock(&mutex)
 *     defer mutex_unlock(&mutex)
 *
 * A fiber holding it may yield or park; others wanting it wait meanwhile.
 */
Mutex :: struct {
    /** Guards the rest, for a few instructions at a time. */
    guard : SpinLock,
    /** Whether someone holds it; it stays true while it's handed from one holder to the next. */
    locked : bool,
    /** The first waiting for it, to get it first, linked to the others through Waiter.next; null when none waits. */
    first : ptr[mut runtime.Waiter]?,
    /** The last waiting for it, which a new waiter is linked after; null when none waits. */
    last : ptr[mut runtime.Waiter]?,
}

/**
 * Lock the mutex, waiting in turn behind those already waiting if it's held.
 *
 * @param mutex The mutex, which the caller holds when this returns, until mutex_unlock.
 */
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

/**
 * Unlock the mutex, handing it straight to the first waiter, if there is one, and waking it.
 *
 * @param mutex The mutex, which the caller must hold. Nothing checks that it does: unlocking one that isn't held hands
 *     it to a waiter, or leaves it unlocked.
 */
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
