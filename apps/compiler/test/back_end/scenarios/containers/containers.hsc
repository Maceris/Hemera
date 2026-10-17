/*
 * std/containers, which need no allocator: main returns 42 if everything worked, or the number of
 * the first check that failed.
 */
package containers_test

import runtime from "base"
import containers from "std"

Task :: struct {
    id : u32,
    queue_link : containers.ListLink,
}

fixed_array :: fn() -> int {
    array : containers.FixedArray[u32, 4]
    for i in 0..<4 {
        if !containers.fixed_push(&array, cast[u32](i * 10)) {
            return 1
        }
    }
    // Full now
    if containers.fixed_push(&array, 99) || array.count != 4 {
        return 2
    }
    // 0, 10, 20, 30, then 10 replaced by the last
    if !containers.fixed_remove_swap(&array, 1) || containers.fixed_remove_swap(&array, 7) {
        return 3
    }
    view :: containers.fixed_view(&array)
    if view.count != 3 || view[0] != 0 || view[1] != 30 || view[2] != 20 {
        return 4
    }
    last :: containers.fixed_pop(&array) or_return 5
    if last != 20 || array.count != 2 {
        return 6
    }
    containers.fixed_clear(&array)
    if containers.fixed_pop(&array) != null {
        return 7
    }
    return 0
}

ring_buffer :: fn() -> int {
    ring : containers.RingBuffer[u32, 3]
    // Around the end several times, in order
    next_in : u32 = 1
    next_out : u32 = 1
    for round in 0..<5 {
        for i in 0..<3 {
            if !containers.ring_push(&ring, next_in) {
                return 11
            }
            next_in += 1
        }
        if containers.ring_push(&ring, 0) {
            return 12
        }
        peeked :: containers.ring_peek(&ring) or_return 13
        if peeked != next_out {
            return 14
        }
        for i in 0..<2 {
            value :: containers.ring_pop(&ring) or_return 15
            if value != next_out {
                return 16
            }
            next_out += 1
        }
        // One left, taken before the next round
        value :: containers.ring_pop(&ring) or_return 17
        if value != next_out {
            return 18
        }
        next_out += 1
    }
    if containers.ring_pop(&ring) != null {
        return 19
    }
    return 0
}

bitmap :: fn() -> int {
    bits : containers.Bitmap[130]
    if bits.words.count != 3 || containers.bit_count(&bits) != 0 {
        return 21
    }
    containers.bit_set(&bits, 0)
    containers.bit_set(&bits, 64)
    containers.bit_set(&bits, 129)
    // Past the end: nothing
    containers.bit_set(&bits, 130)
    if !containers.bit_test(&bits, 64) || containers.bit_test(&bits, 63) || containers.bit_test(&bits, 130)
        || containers.bit_count(&bits) != 3 {
        return 22
    }
    first_set :: containers.bit_find_set(&bits, 1) or_return 23
    second_set :: containers.bit_find_set(&bits, 65) or_return 24
    if first_set != 64 || second_set != 129 || containers.bit_find_set(&bits, 130) != null {
        return 25
    }
    first_clear :: containers.bit_find_clear(&bits, 0) or_return 26
    if first_clear != 1 {
        return 27
    }
    // All set but one, which is found
    for i in 0..<cast[usize](130) {
        containers.bit_set(&bits, i)
    }
    containers.bit_clear(&bits, 100)
    found :: containers.bit_find_clear(&bits, 0) or_return 28
    if found != 100 || containers.bit_count(&bits) != 129 {
        return 29
    }
    containers.bit_set(&bits, 100)
    if containers.bit_find_clear(&bits, 0) != null {
        return 30
    }
    containers.bit_clear_all(&bits)
    if containers.bit_count(&bits) != 0 {
        return 31
    }
    return 0
}

list :: fn() -> int {
    ready : containers.List
    tasks : ptr[mut Task][4]
    for i in 0..<4 {
        task :: runtime.new(Task)
        task.id = cast[u32](i + 1)
        tasks[i] = task
    }
    // 2, 1, 3, 4
    containers.list_push_back(&ready, &tasks[0].queue_link)
    containers.list_push_front(&ready, &tasks[1].queue_link)
    containers.list_push_back(&ready, &tasks[2].queue_link)
    containers.list_push_back(&ready, &tasks[3].queue_link)
    // Out of the middle: 2, 3, 4
    containers.list_remove(&ready, &tasks[0].queue_link)
    if ready.count != 3 {
        return 41
    }
    expected : u32[3]
    expected[0] = 2
    expected[1] = 3
    expected[2] = 4
    for i in 0..<3 {
        link :: containers.list_pop_front(&ready) or_return 42
        task :: containers.entry_of[Task](link, offset_of(Task, queue_link))
        if task.id != expected[i] {
            return 43
        }
    }
    if containers.list_pop_front(&ready) != null || ready.count != 0 {
        return 44
    }
    for i in 0..<4 {
        runtime.free(tasks[i])
    }
    return 0
}

main :: fn() -> int {
    failure := fixed_array()
    if failure == 0 {
        failure = ring_buffer()
    }
    if failure == 0 {
        failure = bitmap()
    }
    if failure == 0 {
        failure = list()
    }
    return if failure == 0 { 42 } else { failure }
}
