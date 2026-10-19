package containers

import compiler from "base"

/*
 * A queue of up to capacity values of T, in the buffer itself: added at the back, taken from the
 * front, in the order they were added. Not safe to share between threads by itself (for that,
 * std/concurrency's Channel).
 *
 *     events : RingBuffer[Event, 32]
 *     ring_push(&events, event)        // false once it's full
 *     next :: ring_pop(&events)        // null once it's empty
 */
RingBuffer :: struct[T, capacity: usize] where compiler.AtLeastOne(capacity) {
    items : T[capacity],
    // Where the oldest value is, and how many there are
    head : usize,
    count : usize,
}

ring_push :: fn[T, capacity: usize](ring: ptr[mut RingBuffer[T, capacity]], value #escaping : T) -> bool {
    if ring.count >= capacity {
        return false
    }
    ring.items[(ring.head + ring.count) % capacity] = value
    ring.count += 1
    return true
}

ring_pop :: fn[T, capacity: usize](ring: ptr[mut RingBuffer[T, capacity]]) -> T? {
    if ring.count == 0 {
        return null
    }
    value :: ring.items[ring.head % capacity]
    ring.head = (ring.head + 1) % capacity
    ring.count -= 1
    return value
}

// The oldest value, without taking it.
ring_peek :: fn[T, capacity: usize](ring: ptr[RingBuffer[T, capacity]]) -> T? {
    if ring.count == 0 {
        return null
    }
    return ring.items[ring.head % capacity]
}

ring_clear :: fn[T, capacity: usize](ring: ptr[mut RingBuffer[T, capacity]]) {
    ring.head = 0
    ring.count = 0
}
