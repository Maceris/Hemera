/*
 * Dynamic arrays: growing, removing, finding and copying, with ints, strings and structs, and
 * every block given back to the allocator it came from.
 */
package arrays_test

import runtime from "base"
import testing from "std"

/** What a counting allocator passes requests on to, and what it's counted. */
Counter :: struct {
    /** The allocator requests are passed on to. */
    parent : runtime.Allocator,
    /** Blocks handed out and not had back. */
    live : int,
    /** Blocks handed out in all, resized ones among them. */
    allocations : int,
}

/**
 * Pass a request on to the Counter's parent, counting the blocks handed out and had back.
 *
 * As runtime.AllocatorFn says; allocator_data is the Counter.
 */
counting_function : runtime.AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (mut u8[], runtime.AllocatorError?) {
    counter :: cast[ptr[mut Counter]](allocator_data)
    if old_memory != null {
        counter.live -= 1
    }
    memory, error :: counter.parent.function(counter.parent.data, size, alignment, old_memory, old_size, location)
    if size > 0 && error == null {
        counter.live += 1
        counter.allocations += 1
    }
    return memory, error
}

/** A struct held in an array. */
Point :: struct {
    /** Any value. */
    x : int,
    /** Any value. */
    y : int,
}

grows_removes_and_finds_ints #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    numbers : int[..]
    defer runtime.array_free(&numbers)
    for i in 0..<100 {
        runtime.array_add(&numbers, i)
    }
    testing.expect_eq(t, numbers.count, 100, "every number added is kept")
    testing.expect_eq(t, numbers.capacity, 128, "the capacity doubles, to the power of two past 100")
    total := 0
    for number in numbers {
        total += number
    }
    testing.expect_eq(t, total, 4950, "0 to 99 add to 4950: each is there once")
    testing.expect_eq(t, runtime.pop(&numbers), 99, "pop takes the last added")
    testing.expect_eq(t, runtime.peek(numbers), 98, "peek sees the new last")
    testing.expect_eq(t, numbers.count, 99, "pop took one")
    // 0 1 2 3 ... 98: removing 0 keeps the order, so 1 is first
    runtime.array_remove(&numbers, 0)
    testing.require_eq(t, numbers.count, 98, "array_remove takes one")?
    if 0 < numbers.count {
        testing.expect_eq(t, numbers[0], 1, "removing in order moves the rest down")
    }
    testing.expect_eq(t, runtime.peek(numbers), 98, "and leaves the last where it was")
    // Removing the first quickly moves the last, 98, into its place
    runtime.array_remove_fast(&numbers, 0)
    testing.require_eq(t, numbers.count, 97, "array_remove_fast takes one")?
    if 0 < numbers.count {
        testing.expect_eq(t, numbers[0], 98, "removing fast moves the last into the gap")
    }
    testing.expect_eq(t, runtime.peek(numbers), 97, "so the one before it is last")
    found :: runtime.array_find(numbers, 50)
    index :: testing.require_some(t, found, "50 is still there")?
    if index < numbers.count {
        testing.expect_eq(t, numbers[index], 50, "array_find gives where it is")
    }
    else {
        testing.fail(t, "array_find gives an index inside the array")
    }
    missing :: runtime.array_find(numbers, 1000)
    testing.expect_none(t, missing, "1000 was never added")
    // Reset keeps the memory
    runtime.array_reset(&numbers)
    testing.expect_eq(t, numbers.count, 0, "a reset empties the array")
    testing.expect_eq(t, numbers.capacity, 128, "but keeps its memory")
    runtime.array_free(&numbers)
    testing.expect_eq(t, numbers.count, 0, "a freed array is empty")
    testing.expect_eq(t, numbers.capacity, 0, "and has no memory")
    return .Ok
}

holds_strings_and_structs #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    names : string[..]
    defer runtime.array_free(&names)
    runtime.array_add(&names, "alpha")
    runtime.array_add(&names, "beta")
    runtime.array_add(&names, "gamma")
    testing.require_eq(t, names.count, 3, "three names added")?
    if names.count == 3 {
        // Read before any call, which could change the array
        second :: names[1]
        third :: names[2]
        // Open slices: from an index to the end, and from the start to one
        start : usize = 2
        from_second :: names[1..].count
        before_second :: names[..<1].count
        through_second :: names[..=1].count
        from_start :: names[start..].count
        testing.expect_eq(t, second.count, 4, "the second is beta")
        testing.expect_eq(t, third, "gamma", "the third is gamma")
        testing.expect_eq(t, from_second, 2, "from the second to the end")
        testing.expect_eq(t, before_second, 1, "up to the second, not including it")
        testing.expect_eq(t, through_second, 2, "up to the second, including it")
        testing.expect_eq(t, from_start, 1, "from a variable index to the end")
    }

    points : Point[..]
    defer runtime.array_free(&points)
    runtime.array_reserve(&points, 10)
    testing.expect_eq(t, points.capacity, 10, "reserve makes room for as many as asked")
    testing.expect_eq(t, points.count, 0, "without adding any")
    for i in 0..<10 {
        runtime.array_add(&points, Point.{x = i, y = i * i})
    }
    // Still in the memory reserve made
    testing.expect_eq(t, points.capacity, 10, "ten fit the room reserved, so it doesn't grow")
    testing.require_eq(t, points.count, 10, "all ten are added")?
    if 9 < points.count {
        testing.expect_eq(t, points[9].y, 81, "the last struct is whole")
    }
    return .Ok
}

copies_from_views_and_arrays #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    fixed : int[3]
    fixed[0] = 7
    fixed[1] = 8
    fixed[2] = 9
    copied : int[..]
    defer runtime.array_free(&copied)
    runtime.array_copy(fixed, &copied)
    runtime.array_copy(copied, &copied)
    testing.require_eq(t, copied.count, 6, "a fixed array's three, then the array's own three again")?
    if copied.count == 6 {
        fourth :: copied[3]
        sixth :: copied[5]
        testing.expect_eq(t, fourth, 7, "copying an array onto itself starts its copy after its end")
        testing.expect_eq(t, sixth, 9, "and copies all it had")
    }
    return .Ok
}

gives_back_every_block #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    counter :: runtime.new(Counter)
    defer runtime.free(counter)
    counter.parent = context.allocator
    counting :: runtime.Allocator.{counting_function, cast[rawptr](counter)}
    push_context counted (allocator = counting) {
        _ = grows_removes_and_finds_ints(t)
        _ = holds_strings_and_structs(t)
        _ = copies_from_views_and_arrays(t)
    }
    testing.expect_eq(t, counter.live, 0, "each array is freed, and growing gives back the block it outgrew")
    testing.expect(t, counter.allocations >= 8, "the arrays grew several times, through the context's allocator")
    return .Ok
}

keeps_the_allocator_it_started_with #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    counter :: runtime.new(Counter)
    defer runtime.free(counter)
    counter.parent = context.allocator
    counting :: runtime.Allocator.{counting_function, cast[rawptr](counter)}
    held : int[..]
    push_context counted (allocator = counting) {
        runtime.array_add(&held, 1)
    }
    before :: counter.allocations
    for i in 0..<10 {
        runtime.array_add(&held, i)
    }
    testing.expect(t, counter.allocations > before, "growing outside the push_context still goes through the counter")
    testing.expect_eq(t, counter.live, 1, "the block outgrown is given back to it too")
    runtime.array_free(&held)
    testing.expect_eq(t, counter.live, 0, "freeing gives the last block back to it")
    return .Ok
}
