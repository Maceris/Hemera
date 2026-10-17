package concurrency

import runtime from "base"

/*
 * Waiting for something a Mutex guards to change, like a queue getting an item. A fiber waiting
 * parks and a thread blocks (runtime.park), the same as for the mutex.
 *
 *     mutex_lock(&mutex)
 *     loop {
 *         condition_wait(&changed, &mutex)
 *     }
 *     while !ready
 *     // ...
 *     mutex_unlock(&mutex)
 *
 * and whoever changes it, with the mutex held, calls condition_signal or condition_broadcast. A
 * wait can end without a signal for it, when another waiter got there first, so wait in a loop.
 */
Condition :: struct {
    // Guards the list, for a few instructions at a time
    guard : SpinLock,
    // Waiting, first to be woken first, linked through Waiter.next
    first : ptr[mut runtime.Waiter]?,
    last : ptr[mut runtime.Waiter]?,
}

/*
 * Unlock the mutex and wait for a signal, then lock it again. It joins the list before unlocking,
 * so a signal from whoever takes the mutex next isn't missed.
 */
condition_wait :: fn(condition: ptr[mut Condition], mutex: ptr[mut Mutex]) {
    waiter :: runtime.current_waiter()
    runtime.prepare_wait(waiter)
    {
        lock(&condition.guard)
        defer unlock(&condition.guard)
        match condition.last {
            case Some(previous) => previous.next = waiter
            case None => condition.first = waiter
        }
        condition.last = waiter
    }
    mutex_unlock(mutex)
    runtime.park(waiter)
    mutex_lock(mutex)
}

// Wake the first waiter, if there is one.
condition_signal :: fn(condition: ptr[mut Condition]) {
    lock(&condition.guard)
    next :: condition.first
    match next {
        case Some(waiter) => {
            condition.first = waiter.next
            if condition.first == null {
                condition.last = null
            }
        }
        case None => {}
    }
    unlock(&condition.guard)
    match next {
        case Some(waiter) => runtime.wake(waiter)
        case None => {}
    }
}

// Wake every waiter.
condition_broadcast :: fn(condition: ptr[mut Condition]) {
    lock(&condition.guard)
    walk := condition.first
    condition.first = null
    condition.last = null
    unlock(&condition.guard)
    loop {
        waiter :: walk or_break
        // Read before waking: once woken, its waiter may be on another list
        walk = waiter.next
        runtime.wake(waiter)
    }
}
