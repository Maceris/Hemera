package concurrency

import compiler from "base"

/**
 * A queue of up to capacity values between fibers and threads.
 *
 * Sending waits while it's full, and receiving waits while it's empty, parking a fiber and blocking a thread
 * (runtime.park). Values come out in the order they went in. Once closed, sending fails, and receiving gives what's
 * left, then fails. Its zero value is an open, empty channel.
 *
 *     jobs : Channel[Job, 64]
 *     channel_send(&jobs, job)              // the job back once it's closed
 *     job, ok :: channel_receive(&jobs)     // ok is false once it's closed and empty
 *     channel_close(&jobs)
 *
 * The values are kept in the channel, so they can't point into a stack.
 *
 * @tparam T The values' type.
 * @tparam capacity How many values it holds before sending waits: at least 1. They're kept in the channel itself, so
 *     it's capacity values large.
 */
Channel :: struct[T, capacity: usize] where compiler.AtLeastOne(capacity) {
    /** Guards the rest. */
    lock : Mutex,
    /** What receivers wait on for a value. */
    not_empty : Condition,
    /** What senders wait on for room. */
    not_full : Condition,
    /** The values, a ring: count of them, from head on, wrapping around. */
    items : T[capacity],
    /** The index in items of the oldest value, below capacity. */
    head : usize,
    /** How many values are in the channel, up to capacity. */
    count : usize,
    /** Whether channel_close was called; once it is, it stays. */
    closed : bool,
}

/**
 * Add a value once there's room, waiting until there is, and wake a receiver.
 *
 * @tparam T The values' type.
 * @tparam capacity How many values the channel holds.
 * @param channel The channel, shared with other fibers and threads.
 * @param value The value, moved into the channel; it may be received on another thread, so it can't point into a
 *     stack.
 * @return What wasn't sent: null once the value is in the channel, or the value back if the channel is closed, before
 *     or while waiting, so a value that's #owned is still the caller's to release (docs/memory.md, Owned Types).
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

/**
 * Take the oldest value, waiting until there is one, and wake a sender.
 *
 * @tparam T The values' type.
 * @tparam capacity How many values the channel holds.
 * @param channel The channel, shared with other fibers and threads.
 * @return The value, now the caller's; the type's zero value when there's none.
 * @return True if a value was taken; false once the channel is closed and has nothing left. A closed channel still
 *     gives what was in it first.
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

/**
 * Close the channel: no more values go in.
 *
 * Senders waiting are woken and fail, given their values back, and receivers get what's left, then fail. Closing
 * twice does no harm.
 *
 * @tparam T The values' type.
 * @tparam capacity How many values the channel holds.
 * @param channel The channel, from any fiber or thread.
 */
channel_close :: fn[T, capacity: usize](channel: ptr[mut Channel[T, capacity]]) {
    mutex_lock(&channel.lock)
    defer mutex_unlock(&channel.lock)
    channel.closed = true
    condition_broadcast(&channel.not_empty)
    condition_broadcast(&channel.not_full)
}
