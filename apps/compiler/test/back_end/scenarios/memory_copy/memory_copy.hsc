/*
 * std/memory's copy: as many elements as both slices have room for, of a type wider than a byte; a source that
 * overlaps the target, before it and after it, copied as it was; and empty slices.
 */
package memory_copy_test

import memory from "std:memory"
import testing from "std:testing"

copies_as_many_as_both_have_room_for #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    from :: u32.[1, 2, 3, 4, 5]
    into := u32.[9, 9, 9]
    testing.expect_eq(t, memory.copy(into[0..<3], from[0..<5]), 3, "the target's room, the smaller")
    testing.expect(t, into[0] == 1 && into[1] == 2 && into[2] == 3, "each element whole, not its first byte")
    wide := u32.[0, 0, 0, 0, 0, 0]
    testing.expect_eq(t, memory.copy(wide[0..<6], from[0..<2]), 2, "the source's count, the smaller")
    testing.expect(t, wide[0] == 1 && wide[1] == 2 && wide[2] == 0, "and what's past it left")
    return .Ok
}

copies_a_source_that_overlaps_as_it_was #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes := u8.[1, 2, 3, 4, 5, 6]
    testing.expect_eq(t, memory.copy(bytes[2..<6], bytes[0..<4]), 4, "forward over itself")
    testing.expect(t, bytes[2] == 1 && bytes[3] == 2 && bytes[4] == 3 && bytes[5] == 4, "the source as it was")
    again := u8.[1, 2, 3, 4, 5, 6]
    testing.expect_eq(t, memory.copy(again[0..<4], again[2..<6]), 4, "back over itself")
    testing.expect(t, again[0] == 3 && again[1] == 4 && again[2] == 5 && again[3] == 6, "the source as it was")
    return .Ok
}

copies_nothing_with_an_empty_slice #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    into := u8.[7]
    testing.expect_eq(t, memory.copy(into[0..<1], u8.[]), 0, "an empty source")
    testing.expect_eq(t, memory.copy(into[0..<0], u8.[5]), 0, "an empty target")
    testing.expect_eq(t, into[0], 7, "nothing written")
    return .Ok
}
