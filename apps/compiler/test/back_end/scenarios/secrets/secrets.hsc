/*
 * Secrets (docs/memory.md, Secrets): a #secret struct and alias, a comparison that looks at every byte,
 * intrinsics.select choosing without a branch, for words and lanes, compiler.secret and declassify, and
 * secure_zero. main returns 42 if they all gave the right answers.
 */
package secrets_test

import compiler from "base"
import intrinsics from "base"

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

main :: fn() -> int {
    first := Key.{bytes = u8.[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]}
    second := first
    if !keys_equal(&first, &second) {
        return 1
    }
    second.bytes[15] = 0
    if keys_equal(&first, &second) {
        return 2
    }
    if compiler.declassify(larger(cast[Word](3), cast[Word](9))) != 9 {
        return 3
    }
    if compiler.declassify(larger(cast[Word](12), cast[Word](9))) != 12 {
        return 4
    }
    mixed := compiler.declassify(mix(cast[Word](1), 2))
    expected := intrinsics.rotate_left(intrinsics.rotate_left(cast[u32](1), 7) ~ 0x9e37_79b9, 7) ~ 0x9e37_79b9
    if mixed != expected {
        return 5
    }
    if lanes(&first) != 2 + 3 + 4 {
        return 6
    }
    intrinsics.secure_zero(&first, size_of(Key))
    if compiler.declassify(first.bytes[0]) != 0 || compiler.declassify(first.bytes[15]) != 0 {
        return 7
    }
    return 42
}
