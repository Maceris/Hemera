/*
 * Secrets used where they could leak (docs/memory.md, Secrets): deciding a branch, a loop, an index,
 * a pointer, whether && runs its right side, or which arm of a match runs; divided; given to, returned
 * as, or stored in what isn't #secret; pointed to as what isn't; a function taking one unmarked; and
 * #secret where it can't be. What's allowed is used too.
 */
package secret_errors

import compiler from "base"
import intrinsics from "base"

Key :: struct #secret {
    bytes: u8[4],
}

Word :: distinct alias u32 #secret
NotDistinct :: alias u32 #secret

TABLE :: u8.[1, 2, 3, 4]

plain :: fn(value: u8) -> u8 {
    return value
}

unmarked :: fn(word: Word) -> Word {
    return word
}

leaks #constant_time :: fn(key: ptr[Key], word: Word) -> u8 {
    if key.bytes[0] == 0 {
        return 0
    }
    for i in 0..<key.bytes[1] {}
    _ = TABLE[key.bytes[2]]
    _ = word / 3
    _ = key.bytes[0] == 1 && true
    match word {
        case 0 => {}
        case _ => {}
    }
    _ = plain(key.bytes[3])
    out : u8 = 0
    out = key.bytes[0]
    _ = &key.bytes
    return key.bytes[1]
}

fine #constant_time :: fn(key: ptr[Key], word: Word) -> Word {
    acc := compiler.secret(cast[u32](0))
    for b in key.bytes {
        acc = acc | cast[u32](b)
    }
    count := key.bytes.count
    for i in 0..<count {
        acc = acc ~ cast[u32](key.bytes[i])
    }
    mixed := intrinsics.select(acc > 3, word, cast[Word](acc))
    _ = compiler.declassify(acc) == 0
    return intrinsics.rotate_left(mixed, 3)
}

nothing_secret #constant_time :: fn(value: u32) -> u32 {
    return value + 1
}

main :: fn() -> int {
    return 0
}
