package concurrency

import intrinsics from "base"
import runtime from "base"

/**
 * A ticket lock: whoever takes the lock gets a ticket and is served in order, so nobody waits forever while others
 * keep taking it.
 *
 * It spins rather than sleeping, so it suits short critical sections where nothing else could run meanwhile, like a
 * kernel with interrupts disabled. Its zero value is unlocked. It isn't reentrant: a holder that locks it again spins
 * forever.
 *
 *     lock(&spin_lock)
 *     defer unlock(&spin_lock)
 */
SpinLock :: struct {
    /** The ticket the next to take the lock gets. Wraps around, which is harmless while fewer wait than 2^32. */
    next_ticket : u32,
    /** The ticket whose holder has the lock, or will once it's taken; the lock is free when it equals next_ticket. */
    now_serving : u32,
}

/**
 * Take the lock, spinning until it's this caller's turn.
 *
 * @param spin_lock The lock, which the caller holds when this returns, until unlock. Writes made under it by earlier
 *     holders are seen.
 */
lock :: fn(spin_lock: ptr[mut SpinLock]) {
    ticket :: intrinsics.interlocked_exchange_add_u32_no_fence(&spin_lock.next_ticket, 1)
    loop {
        // A recording's turn, in the deterministic mode, so the holder can run
        runtime.deterministic_turn()
        intrinsics.spin_hint()
    }
    while intrinsics.atomic_load_u32_acquire(&spin_lock.now_serving) != ticket
}

/** What lock_waiting calls while it waits: a function, and what it's given. */
Waiting :: struct {
    /**
     * Called each time round the spin, with state. It mustn't take the lock being waited for, which would wait for
     * itself; it may return, or not.
     */
    call : (fn(state: rawptr)),
    /** What call is given, which lock_waiting only passes on: any address, null included. */
    state : rawptr,
}

/**
 * Take the lock as lock does, calling waiting each time round the spin while it isn't this caller's turn: for a caller
 * that has to keep watch while it waits, like a kernel with interrupts off checking for a CPU that's stopped, which
 * could be the one holding the lock.
 *
 * @param spin_lock The lock, which the caller holds when this returns, until unlock. Writes made under it by earlier
 *     holders are seen.
 * @param waiting Called while the caller waits, after its ticket is taken, never once the lock is the caller's: not at
 *     all when the lock is free at once.
 */
lock_waiting :: fn(spin_lock: ptr[mut SpinLock], waiting: Waiting) {
    ticket :: intrinsics.interlocked_exchange_add_u32_no_fence(&spin_lock.next_ticket, 1)
    loop {
        if intrinsics.atomic_load_u32_acquire(&spin_lock.now_serving) == ticket {
            return void
        }
        runtime.deterministic_turn()
        waiting.call(waiting.state)
        intrinsics.spin_hint()
    }
}

/**
 * Give back the lock, serving the next ticket.
 *
 * @param spin_lock The lock, which the caller must hold: nothing checks that it does, and unlocking one that isn't
 *     held lets a later caller in early.
 */
unlock :: fn(spin_lock: ptr[mut SpinLock]) {
    // Only the holder writes now_serving
    serving :: intrinsics.atomic_load_u32_no_fence(&spin_lock.now_serving)
    intrinsics.atomic_store_u32_release(&spin_lock.now_serving, serving + 1)
}
