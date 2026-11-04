package concurrency

import runtime from "base"

/**
 * Waiting for something a Mutex guards to change, like a queue getting an item.
 *
 * A fiber waiting parks and a thread blocks (runtime.park), the same as for the mutex. Its zero value has no waiters.
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
    /** Guards the list, for a few instructions at a time. */
    guard : SpinLock,
    /** The first waiter, to be woken first, linked to the others through Waiter.next; null when none waits. */
    first : ptr[mut runtime.Waiter]?,
    /** The last waiter, which a new one is linked after; null when none waits. */
    last : ptr[mut runtime.Waiter]?,
}

/**
 * Unlock the mutex and wait for a signal, then lock it again.
 *
 * It joins the list before unlocking, so a signal from whoever takes the mutex next isn't missed. A wait can end
 * without a signal for it, when another waiter got there first, so the caller checks what it waits for in a loop.
 *
 * @param condition The condition, shared with whoever signals it.
 * @param mutex The mutex guarding what's waited for, which the caller must hold; it's held again when this returns.
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

/**
 * Wake the first waiter, if there is one.
 *
 * @param condition The condition. The caller should hold the mutex its waiters use, having changed what they wait
 *     for, so the change isn't missed.
 */
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

/**
 * Wake every waiter. Each takes the mutex again in turn before its wait returns.
 *
 * @param condition The condition. The caller should hold the mutex its waiters use, having changed what they wait
 *     for.
 */
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
