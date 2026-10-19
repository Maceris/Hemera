package concurrency

import compiler from "base"

/*
 * A queue of up to capacity values between fibers and threads: sending waits while it's full, and
 * receiving waits while it's empty, parking a fiber and blocking a thread (runtime.park). Values
 * come out in the order they went in. Once closed, sending fails, and receiving gives what's left,
 * then fails.
 *
 *     jobs : Channel[Job, 64]
 *     channel_send(&jobs, job)              // the job back once it's closed
 *     job, ok :: channel_receive(&jobs)     // ok is false once it's closed and empty
 *     channel_close(&jobs)
 *
 * The values are kept in the channel, so they can't point into a stack.
 */
Channel :: struct[T, capacity: usize] where compiler.AtLeastOne(capacity) {
    lock : Mutex,
    // Waiting for a value, and for room
    not_empty : Condition,
    not_full : Condition,
    items : T[capacity],
    // Where the oldest value is, and how many there are
    head : usize,
    count : usize,
    closed : bool,
}

/*
 * Add a value once there's room, waiting until there is. What wasn't sent: null once the value is in the
 * channel, or the value back if the channel is closed, before or while waiting, so a value that's
 * #owned is still the caller's to release (docs/memory.md, Owned Types).
 */
channel_send :: fn[T, capacity: usize](channel: ptr[mut Channel[T, capacity]], value #escaping #crosses_threads : T) -> T? {
    mutex_lock(&channel.lock)
    defer mutex_unlock(&channel.lock)
    loop {
        if channel.closed {
            return value
        }
        if channel.count < capacity {
            break
        }
        condition_wait(&channel.not_full, &channel.lock)
    }
    channel.items[(channel.head + channel.count) % capacity] = value
    channel.count += 1
    condition_signal(&channel.not_empty)
    return null
}

/*
 * Take the oldest value, waiting until there is one. Its second result is false once the channel is
 * closed and has nothing left, and then the first is the type's zero value.
 */
channel_receive :: fn[T, capacity: usize](channel: ptr[mut Channel[T, capacity]]) -> (T, bool) {
    mutex_lock(&channel.lock)
    defer mutex_unlock(&channel.lock)
    loop {
        if channel.count > 0 {
            break
        }
        if channel.closed {
            nothing : T
            return nothing, false
        }
        condition_wait(&channel.not_empty, &channel.lock)
    }
    value :: channel.items[channel.head % capacity]
    channel.head = (channel.head + 1) % capacity
    channel.count -= 1
    condition_signal(&channel.not_full)
    return value, true
}

// No more values: waiting senders fail, and receivers get what's left, then fail.
channel_close :: fn[T, capacity: usize](channel: ptr[mut Channel[T, capacity]]) {
    mutex_lock(&channel.lock)
    defer mutex_unlock(&channel.lock)
    channel.closed = true
    condition_broadcast(&channel.not_empty)
    condition_broadcast(&channel.not_full)
}
