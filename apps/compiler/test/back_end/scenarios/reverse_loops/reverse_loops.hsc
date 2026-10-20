/*
 * for loops with #reverse (docs/control_flow.md, Range-based for): ..< and ..=, signed and unsigned,
 * empty ranges, an unsigned range down to 0 without wrapping, an array's elements by value and by
 * reference, continue and break, and an index the bounds prover still proves. main returns 42 if they
 * all went last to first.
 */
package reverse_loops_test

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

main :: fn() -> int {
    errors := 0

    // 9, 8, ..., 1: each digit shifts the earlier ones up
    digits : u64 = 0
    for i in 1..<10 #reverse {
        digits = digits * 10 + cast[u64](i)
    }
    errors += check(digits == 987654321, 1)

    // ..= takes the last one too, down to an unsigned 0
    sum : u32 = 0
    count := 0
    last : u32 = 99
    for i in cast[u32](0)..=5 #reverse {
        sum += i
        count += 1
        last = i
    }
    errors += check(sum == 15 && count == 6 && last == 0, 2)

    // Signed, across 0
    order := 0
    for i in -2..=2 #reverse {
        order = order * 10 + (i + 3)
    }
    errors += check(order == 54321, 3)

    // Empty ranges go around no times
    none := 0
    for i in 5..<5 #reverse {
        none += 1
    }
    for i in cast[u8](3)..=2 #reverse {
        none += 1
    }
    errors += check(none == 0, 4)

    // The whole of u8, ending at 0
    bytes := 0
    for i in cast[u8](0)..=255 #reverse {
        bytes += 1
    }
    errors += check(bytes == 256, 5)

    // An array's elements, last first, by value and with their index
    values := int.[1, 2, 3, 4]
    seen := 0
    for value, index in values #reverse {
        seen = seen * 10 + value
        if index == 0 {
            seen = seen * 10
        }
    }
    errors += check(seen == 43210, 6)

    // By reference
    for &value in values #reverse {
        value^ = value^ * 2
    }
    errors += check(values[0] == 2 && values[3] == 8, 7)

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
    errors += check(picked == 864, 8)

    // Indexing with the loop's name is still proven in bounds
    table := int.[10, 20, 30, 40, 50]
    total := 0
    for i in 1..<5 #reverse {
        total += table[i]
    }
    errors += check(total == 140, 9)

    if errors != 0 {
        return errors
    }
    return 42
}
