/*
 * Constants where types and values meet: #run as an array's count, a multi-dimensional array type in an expression,
 * a string literal's members, and #file_path (docs/compilation.md, docs/types.md, docs/directives.md).
 */
package constant_sizes

import testing from "std"

/**
 * Work out a Fibonacci number the slow way, for #run to give an array's count.
 *
 * @param n Which number, from 0; below 2 it's n itself.
 * @return The nth Fibonacci number.
 */
fib :: fn(n: int) -> int {
    return if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}

/** A ring of items whose capacity is a constant parameter. */
Ring :: struct[T, capacity: usize] {
    /** The items, capacity of them. */
    items : T[capacity],
}

/**
 * Tell whether text ends with suffix.
 *
 * @param text The text looked at.
 * @param suffix What it should end with; empty ends everything.
 * @return Whether text's last suffix.count bytes are suffix's.
 */
ends_with :: fn(text: string, suffix: string) -> bool {
    if suffix.count > text.count {
        return false
    }
    for i in 0..<suffix.count {
        at :: text.count - suffix.count + i
        if at < text.count && text[at] != suffix[i] {
            return false
        }
    }
    return true
}

sizes_arrays_by_run #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    numbers : int[#run fib(5)]
    testing.expect_eq(t, numbers.count, 5, "the fifth Fibonacci number is 5")
    ring : Ring[u8, #run fib(6)]
    testing.expect_eq(t, ring.items.count, 8, "a constant parameter takes #run's value too: the sixth is 8")
    return .Ok
}

sizes_multi_dimensional_array_types #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, size_of(i8[10][5]), 50, "fifty one-byte elements")
    testing.expect_eq(t, size_of(u16[3][2][2]), 24, "twelve two-byte elements")
    return .Ok
}

reads_a_string_literals_members #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, "abc".count, 3, "three bytes")
    testing.expect_eq(t, "abc"[1], 'b', "the second is b")
    return .Ok
}

gives_the_files_path #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    path :: #file_path
    testing.expect(t, ends_with(path, "constant_sizes.hsc"), "#file_path names the file it's in")
    return .Ok
}
