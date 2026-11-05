/*
 * for loops with #reverse (docs/control_flow.md, Range-based for): ..< and ..=, signed and unsigned,
 * empty ranges, an unsigned range down to 0 without wrapping, an array's elements by value and by
 * reference, continue and break, and an index the bounds prover still proves.
 */
package reverse_loops_test

import testing from "std"

goes_down_ranges #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // 9, 8, ..., 1: each digit shifts the earlier ones up
    digits : u64 = 0
    for i in 1..<10 #reverse {
        digits = digits * 10 + cast[u64](i)
    }
    testing.expect_eq(t, digits, 987654321, "..< #reverse goes from the last below the end down to the start")

    // ..= takes the last one too, down to an unsigned 0
    sum : u32 = 0
    count := 0
    last : u32 = 99
    for i in cast[u32](0)..=5 #reverse {
        sum += i
        count += 1
        last = i
    }
    testing.expect_eq(t, sum, 15, "..= #reverse takes 5 too")
    testing.expect_eq(t, count, 6, "it goes around once for each of 5 down to 0")
    testing.expect_eq(t, last, 0, "it stops at an unsigned 0 without wrapping")

    // Signed, across 0
    order := 0
    for i in -2..=2 #reverse {
        order = order * 10 + (i + 3)
    }
    testing.expect_eq(t, order, 54321, "a signed range goes down across 0")

    // The whole of u8, ending at 0
    bytes := 0
    for i in cast[u8](0)..=255 #reverse {
        bytes += 1
    }
    testing.expect_eq(t, bytes, 256, "the whole of u8 goes from 255 down to 0, once each, without wrapping")
    return .Ok
}

goes_around_empty_ranges_no_times #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    none := 0
    for i in 5..<5 #reverse {
        none += 1
    }
    for i in cast[u8](3)..=2 #reverse {
        none += 1
    }
    testing.expect_eq(t, none, 0, "a range whose end is at or before its start is empty, reversed or not")
    return .Ok
}

goes_through_arrays_last_first #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // By value and with their index
    values := int.[1, 2, 3, 4]
    seen := 0
    for value, index in values #reverse {
        seen = seen * 10 + value
        if index == 0 {
            seen = seen * 10
        }
    }
    testing.expect_eq(t, seen, 43210, "the elements go last first, the index 0 with the first, last")

    // By reference
    for &value in values #reverse {
        value^ = value^ * 2
    }
    testing.expect(t, values[0] == 2 && values[3] == 8, "each element is reached through its pointer, the first and last too")

    // Indexing with the loop's name is still proven in bounds
    table := int.[10, 20, 30, 40, 50]
    total := 0
    for i in 1..<5 #reverse {
        total += table[i]
    }
    testing.expect_eq(t, total, 140, "indexes 4 down to 1 reach every element but the first")
    return .Ok
}

continues_and_breaks #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // continue moves on to the next lower, break stops
    picked := 0
    for i in 0..<10 #reverse {
        if i % 2 == 1 {
            continue
        }
        if i < 4 {
            break
        }
        picked = picked * 10 + i
    }
    testing.expect_eq(t, picked, 864, "the odd ones are skipped and it stops below 4")
    return .Ok
}
