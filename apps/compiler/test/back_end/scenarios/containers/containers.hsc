/*
 * std/containers, which need no allocator: a fixed array, a ring buffer, a bitmap and an intrusive list.
 */
package containers_test

import runtime from "base"
import containers from "std"
import testing from "std"

/** Something queued on an intrusive list. */
Task :: struct {
    /** Which task it is; any value. */
    id : u32,
    /** Its place in a list. */
    queue_link : containers.ListLink,
}

fills_and_empties_a_fixed_array #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    array : containers.FixedArray[u32, 4]
    for i in 0..<4 {
        testing.require(t, containers.fixed_push(&array, cast[u32](i * 10)), "a fixed array of four has room for four")?
    }
    testing.expect(t, !containers.fixed_push(&array, 99), "a fifth doesn't fit")
    testing.expect_eq(t, array.count, 4, "and isn't counted")
    // 0, 10, 20, 30, then 10 replaced by the last
    testing.expect(t, containers.fixed_remove_swap(&array, 1), "the second is there to remove")
    testing.expect(t, !containers.fixed_remove_swap(&array, 7), "there's no eighth to remove")
    view :: containers.fixed_view(&array)
    testing.require_eq(t, view.count, 3, "one of four was removed")?
    if view.count == 3 {
        kept :: u32.[view[0], view[1], view[2]]
        testing.expect_eq(t, kept, u32.[0, 30, 20], "removing by swapping moves the last into the gap")
    }
    last :: testing.require_some(t, containers.fixed_pop(&array), "three are left to pop")?
    testing.expect_eq(t, last, 20, "pop takes the last")
    testing.expect_eq(t, array.count, 2, "leaving two")
    containers.fixed_clear(&array)
    testing.expect_none(t, containers.fixed_pop(&array), "a cleared array has nothing to pop")
    return .Ok
}

goes_around_a_ring_buffer_in_order #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    ring : containers.RingBuffer[u32, 3]
    // Around the end several times, in order
    next_in : u32 = 1
    next_out : u32 = 1
    for round in 0..<5 {
        for i in 0..<3 {
            testing.require(t, containers.ring_push(&ring, next_in), "an emptied ring of three has room for three")?
            next_in += 1
        }
        testing.expect(t, !containers.ring_push(&ring, 0), "a full ring takes no more")
        peeked :: testing.require_some(t, containers.ring_peek(&ring), "a full ring has a first to peek at")?
        testing.expect_eq(t, peeked, next_out, "peek sees the oldest")
        for i in 0..<2 {
            value :: testing.require_some(t, containers.ring_pop(&ring), "a full ring has values to pop")?
            testing.expect_eq(t, value, next_out, "values come out in the order they went in")
            next_out += 1
        }
        // One left, taken before the next round
        value :: testing.require_some(t, containers.ring_pop(&ring), "one is left")?
        testing.expect_eq(t, value, next_out, "the last comes out last")
        next_out += 1
    }
    testing.expect_none(t, containers.ring_pop(&ring), "everything pushed was popped")
    return .Ok
}

sets_finds_and_counts_bits #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bits : containers.Bitmap[130]
    testing.expect_eq(t, bits.words.count, 3, "130 bits take three 64-bit words")
    testing.expect_eq(t, containers.bit_count(&bits), 0, "a new bitmap is clear")
    containers.bit_set(&bits, 0)
    containers.bit_set(&bits, 64)
    containers.bit_set(&bits, 129)
    // Past the end: nothing
    containers.bit_set(&bits, 130)
    testing.expect(t, containers.bit_test(&bits, 64), "a bit set in the second word")
    testing.expect(t, !containers.bit_test(&bits, 63), "the bit before it isn't")
    testing.expect(t, !containers.bit_test(&bits, 130), "a bit past the end is never set")
    testing.expect_eq(t, containers.bit_count(&bits), 3, "setting past the end did nothing")
    testing.expect_eq(t, containers.bit_find_set(&bits, 1), cast[usize?](64), "the first set from 1 is across a word")
    testing.expect_eq(t, containers.bit_find_set(&bits, 65), cast[usize?](129), "the last bit is found")
    testing.expect_none(t, containers.bit_find_set(&bits, 130), "nothing is found from past the end")
    testing.expect_eq(t, containers.bit_find_clear(&bits, 0), cast[usize?](1), "0 is set, so 1 is the first clear")
    // All set but one, which is found
    for i in 0..<cast[usize](130) {
        containers.bit_set(&bits, i)
    }
    containers.bit_clear(&bits, 100)
    testing.expect_eq(t, containers.bit_find_clear(&bits, 0), cast[usize?](100), "the one bit cleared")
    testing.expect_eq(t, containers.bit_count(&bits), 129, "all but that one")
    containers.bit_set(&bits, 100)
    testing.expect_none(t, containers.bit_find_clear(&bits, 0), "with every bit set, none is clear: the unused ones don't count")
    containers.bit_clear_all(&bits)
    testing.expect_eq(t, containers.bit_count(&bits), 0, "clearing all clears every word")
    return .Ok
}

links_a_list_through_its_entries #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    ready : containers.List
    tasks : ptr[mut Task][4]
    for i in 0..<4 {
        task :: runtime.new(Task)
        task.id = cast[u32](i + 1)
        tasks[i] = task
    }
    defer {
        for i in 0..<4 {
            runtime.free(tasks[i])
        }
    }
    // 2, 1, 3, 4
    containers.list_push_back(&ready, &tasks[0].queue_link)
    containers.list_push_front(&ready, &tasks[1].queue_link)
    containers.list_push_back(&ready, &tasks[2].queue_link)
    containers.list_push_back(&ready, &tasks[3].queue_link)
    // Out of the middle: 2, 3, 4
    containers.list_remove(&ready, &tasks[0].queue_link)
    testing.expect_eq(t, ready.count, 3, "one of four was removed")
    expected :: u32.[2, 3, 4]
    for id in expected {
        link :: testing.require_some(t, containers.list_pop_front(&ready), "three are left to pop")?
        task :: containers.entry_of[Task](link, offset_of(Task, queue_link))
        testing.expect_eq(t, task.id, id, "pushed to the front, then the back in order, less the one removed")
    }
    testing.expect_none(t, containers.list_pop_front(&ready), "all three were popped")
    testing.expect_eq(t, ready.count, 0, "and the count says so")
    return .Ok
}
