/*
 * #union struct literals (docs/types.md, Structs): its members overlap, so a literal sets the one it names, and the
 * rest reads those bytes. main returns 42 if they all held, or the number of the first that didn't.
 */
package union_literals

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

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

main :: fn() -> int {
    errors := 0
    word := Overlay.{word = 0x01020304}
    errors += check(word.bytes[0] == 4 && word.bytes[3] == 1 && word.halves[1] == 0x0102, 1)
    bytes := Overlay.{bytes = u8.[1, 0, 0, 0]}
    errors += check(bytes.word == 1, 2)
    status := Status.{raw = 0x00050001}
    errors += check(status.ready == 1 && status.error == 0 && status.count == 5, 3)
    empty := Overlay.{}
    errors += check(empty.word == 0, 4)
    if errors == 0 {
        return 42
    }
    return errors
}
