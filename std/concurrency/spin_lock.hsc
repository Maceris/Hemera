package concurrency

import intrinsics from "base"

/*
 * A ticket lock: whoever takes the lock gets a ticket and is served in order, so nobody waits
 * forever while others keep taking it. It spins rather than sleeping, so it suits short critical
 * sections where nothing else could run meanwhile, like a kernel with interrupts disabled.
 *
 *     lock(&spin_lock)
 *     defer unlock(&spin_lock)
 */
SpinLock :: struct {
    next_ticket : u32,
    now_serving : u32,
}

lock :: fn(spin_lock: ptr[mut SpinLock]) {
    ticket :: intrinsics.interlocked_exchange_add_u32_no_fence(&spin_lock.next_ticket, 1)
    loop {
        intrinsics.spin_hint()
    }
    while intrinsics.atomic_load_u32_acquire(&spin_lock.now_serving) != ticket
}

unlock :: fn(spin_lock: ptr[mut SpinLock]) {
    // Only the holder writes now_serving
    serving :: intrinsics.atomic_load_u32_no_fence(&spin_lock.now_serving)
    intrinsics.atomic_store_u32_release(&spin_lock.now_serving, serving + 1)
}
