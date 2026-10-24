/*
 * Dynamic arrays: growing, removing, finding and copying, with ints, strings and structs, and
 * every block given back to the allocator it came from. main returns 42 if everything worked, or
 * the number of the first check that failed.
 */
package arrays_test

import runtime from "base"

// How many blocks a counting allocator has handed out and not had back.
Counter :: struct {
    parent : runtime.Allocator,
    live : int,
    allocations : int,
}

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

Point :: struct {
    x : int,
    y : int,
}

// Ints: growth, pop, removal in order and out of order, finding. 0 if it all worked.
check_ints :: fn() -> int {
    numbers : int[..]
    for i in 0..<100 {
        runtime.array_add(&numbers, i)
    }
    if numbers.count != 100 || numbers.capacity != 128 {
        return 1
    }
    total := 0
    for number in numbers {
        total += number
    }
    if total != 4950 {
        return 2
    }
    if runtime.pop(&numbers) != 99 || runtime.peek(numbers) != 98 || numbers.count != 99 {
        return 3
    }
    // 0 1 2 3 ... 98: removing 0 keeps the order, so 1 is first
    runtime.array_remove(&numbers, 0)
    if numbers.count != 98 || numbers.count == 0 || numbers[0] != 1 || runtime.peek(numbers) != 98 {
        return 4
    }
    // Removing the first quickly moves the last, 98, into its place
    runtime.array_remove_fast(&numbers, 0)
    if numbers.count != 97 || numbers.count == 0 || numbers[0] != 98 || runtime.peek(numbers) != 97 {
        return 5
    }
    match runtime.array_find(numbers, 50) {
        case Some(index) => {
            if index >= numbers.count || numbers[index] != 50 {
                return 6
            }
        }
        case None => return 6
    }
    if runtime.array_find(numbers, 1000) != null {
        return 7
    }
    // Reset keeps the memory
    runtime.array_reset(&numbers)
    if numbers.count != 0 || numbers.capacity != 128 {
        return 8
    }
    runtime.array_free(&numbers)
    if numbers.count != 0 || numbers.capacity != 0 {
        return 9
    }
    return 0
}

// Strings and structs, and copying from views and other arrays. 0 if it all worked.
check_elements :: fn() -> int {
    names : string[..]
    runtime.array_add(&names, "alpha")
    runtime.array_add(&names, "beta")
    runtime.array_add(&names, "gamma")
    if names.count != 3 || names[1].count != 4 || names[2].count == 0 || names[2][0] != 'g' {
        return 1
    }
    // Open slices: from an index to the end, and from the start to one
    if names[1..].count != 2 || names[..<1].count != 1 || names[..=1].count != 2 {
        return 1
    }
    start : usize = 2
    if names[start..].count != 1 {
        return 1
    }
    runtime.array_free(&names)

    points : Point[..]
    runtime.array_reserve(&points, 10)
    if points.capacity != 10 || points.count != 0 {
        return 2
    }
    for i in 0..<10 {
        runtime.array_add(&points, Point.{x = i, y = i * i})
    }
    // Still in the memory reserve made
    if points.capacity != 10 || points.count != 10 || points[9].y != 81 {
        return 3
    }
    fixed : int[3]
    fixed[0] = 7
    fixed[1] = 8
    fixed[2] = 9
    copied : int[..]
    runtime.array_copy(fixed, &copied)
    runtime.array_copy(copied, &copied)
    if copied.count != 6 || copied[3] != 7 || copied[5] != 9 {
        return 4
    }
    runtime.array_free(&copied)
    runtime.array_free(&points)
    return 0
}

main :: fn() -> int {
    counter :: runtime.new(Counter)
    counter.parent = context.allocator
    counting :: runtime.Allocator.{counting_function, cast[rawptr](counter)}
    push_context counted (allocator = counting) {
        failure := check_ints()
        if failure != 0 {
            return 10 + failure
        }
        failure = check_elements()
        if failure != 0 {
            return 20 + failure
        }
    }
    // Every block given back, after growing several times
    if counter.live != 0 || counter.allocations < 8 {
        return 30
    }
    // The array keeps the allocator it started with, even where the context's is another
    held : int[..]
    push_context counted (allocator = counting) {
        runtime.array_add(&held, 1)
    }
    before :: counter.allocations
    for i in 0..<10 {
        runtime.array_add(&held, i)
    }
    if counter.allocations <= before || counter.live != 1 {
        return 31
    }
    runtime.array_free(&held)
    if counter.live != 0 {
        return 32
    }
    runtime.free(counter)
    return 42
}
