/*
 * #union struct literals (docs/types.md, Structs): its members overlap, so a literal sets the one it names, and the
 * rest reads those bytes.
 */
package union_literals

import testing from "std"

Overlay :: struct #union {
    word : u32,
    bytes : u8[4],
    halves : u16[2],
}

// A register as a device lays it out, a word or its fields
Status :: struct #union {
    raw : u32,
    _ : struct #packed {
        ready : u8,
        error : u8,
        count : u16,
    },
}

sets_the_member_it_names #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    word := Overlay.{word = 0x01020304}
    testing.expect(t, word.bytes[0] == 4 && word.bytes[3] == 1, "a word's bytes read little-endian, through the array over it")
    testing.expect_eq(t, word.halves[1], 0x0102, "its high half reads through the halves over it")
    bytes := Overlay.{bytes = u8.[1, 0, 0, 0]}
    testing.expect_eq(t, bytes.word, 1, "bytes set read back as the word over them")
    status := Status.{raw = 0x00050001}
    testing.expect(t, status.ready == 1 && status.error == 0 && status.count == 5, "a raw register reads back through the anonymous struct's fields")
    empty := Overlay.{}
    testing.expect_eq(t, empty.word, 0, "a literal naming nothing is zeros")
    return .Ok
}
