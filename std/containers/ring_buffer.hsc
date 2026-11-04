package containers

import compiler from "base"

/**
 * A queue of up to capacity values of T, in the buffer itself: added at the back, taken from the front, in the order
 * they were added.
 *
 * Its zero value is empty. It's not safe to share between threads by itself (for that, std/concurrency's Channel).
 *
 *     events : RingBuffer[Event, 32]
 *     ring_push(&events, event)        // false once it's full
 *     next :: ring_pop(&events)        // null once it's empty
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds: at least 1. They're kept in the buffer itself, so it's capacity values
 *     large.
 */
RingBuffer :: struct[T, capacity: usize] where compiler.AtLeastOne(capacity) {
    /** The values: count of them, from head on, wrapping around. */
    items : T[capacity],
    /** The index in items of the oldest value, below capacity. */
    head : usize,
    /** How many values it holds, from 0 to capacity. */
    count : usize,
}

/**
 * Add a value at the back, unless it's full.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param ring A buffer to add to; when it has room, its count grows by one.
 * @param value The value, copied in.
 * @return True if it was added; false if the buffer was full, leaving it unchanged.
 */
ring_push :: fn[T, capacity: usize](ring: ptr[mut RingBuffer[T, capacity]], value #escaping : T) -> bool {
    if ring.count >= capacity {
        return false
    }
    ring.items[(ring.head + ring.count) % capacity] = value
    ring.count += 1
    return true
}

/**
 * Take the oldest value, from the front.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param ring A buffer to take from; when it isn't empty, its head moves on by one, wrapping around, and its count
 *     shrinks by one.
 * @return The oldest value, removed; null if the buffer is empty.
 */
ring_pop :: fn[T, capacity: usize](ring: ptr[mut RingBuffer[T, capacity]]) -> T? {
    if ring.count == 0 {
        return null
    }
    value :: ring.items[ring.head % capacity]
    ring.head = (ring.head + 1) % capacity
    ring.count -= 1
    return value
}

/**
 * Look at the oldest value, without taking it.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param ring A buffer to look in; it isn't changed.
 * @return A copy of the oldest value; null if the buffer is empty.
 */
ring_peek :: fn[T, capacity: usize](ring: ptr[RingBuffer[T, capacity]]) -> T? {
    if ring.count == 0 {
        return null
    }
    return ring.items[ring.head % capacity]
}

/**
 * Empty the buffer. The values aren't cleared or released, only forgotten.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param ring A buffer to empty; its head and count become 0.
 */
ring_clear :: fn[T, capacity: usize](ring: ptr[mut RingBuffer[T, capacity]]) {
    ring.head = 0
    ring.count = 0
}
