/*
 * Secrets (docs/memory.md, Secrets): a #secret struct and alias, a comparison that looks at every byte,
 * intrinsics.select choosing without a branch, for words and lanes, compiler.secret and declassify, and
 * secure_zero.
 */
package secrets_test

import compiler from "base"
import intrinsics from "base"
import testing from "std"

Key :: struct #secret {
    bytes: u8[16],
}

Word :: distinct alias u32 #secret

// Whether two keys are equal, looking at every byte whatever it finds
keys_equal #constant_time :: fn(a: ptr[Key], b: ptr[Key]) -> bool {
    difference := compiler.secret(cast[u8](0))
    for i in 0..<16 {
        difference = difference | (a.bytes[i] ~ b.bytes[i])
    }
    return compiler.declassify(difference == 0)
}

// The larger of two words, chosen without a branch
larger #constant_time :: fn(a: Word, b: Word) -> Word {
    return intrinsics.select(a > b, a, b)
}

mix #constant_time :: fn(word: Word, rounds: int) -> Word {
    result := word
    for round in 0..<rounds {
        result = intrinsics.rotate_left(result, 7) ~ cast[Word](0x9e37_79b9)
    }
    return result
}

lanes #constant_time :: fn(key: ptr[Key]) -> u32 {
    words := vector[u32, 4].{cast[u32](key.bytes[0]), cast[u32](key.bytes[1]), cast[u32](key.bytes[2]), cast[u32](key.bytes[3])}
    big := words > vector[u32, 4].{1, 1, 1, 1}
    picked := intrinsics.select(big, words, vector[u32, 4].{})
    return compiler.declassify(intrinsics.reduce_add(picked))
}

compares_keys_byte_by_byte #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    first := Key.{bytes = u8.[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]}
    second := first
    testing.expect(t, keys_equal(&first, &second), "a copy of a key is equal to it")
    second.bytes[15] = 0
    testing.expect(t, !keys_equal(&first, &second), "keys differing only in their last byte differ: every byte is looked at")
    return .Ok
}

chooses_without_branching #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, compiler.declassify(larger(cast[Word](3), cast[Word](9))), 9, "select gives the second when the first isn't larger")
    testing.expect_eq(t, compiler.declassify(larger(cast[Word](12), cast[Word](9))), 12, "select gives the first when it's larger")
    mixed := compiler.declassify(mix(cast[Word](1), 2))
    expected := intrinsics.rotate_left(intrinsics.rotate_left(cast[u32](1), 7) ~ 0x9e37_79b9, 7) ~ 0x9e37_79b9
    testing.expect_eq(t, mixed, expected, "a secret word rotates and mixes as a plain u32 does")
    first := Key.{bytes = u8.[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]}
    testing.expect_eq(t, lanes(&first), 2 + 3 + 4, "select on lanes keeps only the bytes above 1, of the first four")
    return .Ok
}

zeroes_a_secret #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    first := Key.{bytes = u8.[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]}
    intrinsics.secure_zero(&first, size_of(Key))
    testing.expect_eq(t, compiler.declassify(first.bytes[0]), 0, "secure_zero clears the key's first byte")
    testing.expect_eq(t, compiler.declassify(first.bytes[15]), 0, "and its last, all size_of(Key) of it")
    return .Ok
}
