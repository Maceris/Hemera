/*
 * Optionals that start zeroed are None (docs/types.md, Optional Types): left out of a struct's literal, in an array of
 * structs, declared without a value, an optional pointer too; and None and Some still behave and format as before.
 * main returns 42 if they did, or the number of the first check that didn't.
 */
package optional_defaults

import text_buffer from "std"

Inner :: struct {
    value : u32?,
}

Outer :: struct {
    direct : u32?,
    nested : Inner,
    many : Inner[4],
    pointer : ptr[int]?,
    count : int,
}

half :: fn(n: u32) -> u32? {
    if n % 2 != 0 {
        return null
    }
    return n / 2
}

main :: fn() -> int {
    made := Outer.{count = 1}
    if (made.direct is_some) || (made.nested.value is_some) || (made.many[2].value is_some) || (made.pointer is_some) {
        return 1
    }
    plain : Outer
    declared : u32?
    if (plain.direct is_some) || (plain.many[1].value is_some) || (declared is_some) || declared != null {
        return 2
    }
    // Some and None as ever
    if (half(4) or_else 0) != 2 || (half(3) is_some) || half(6) != 3 {
        return 3
    }
    match half(8) {
        case Some(n) => {
            if n != 4 {
                return 4
            }
        }
        case None => return 4
    }
    made.direct = 7
    if made.direct != 7 || made.direct == null {
        return 5
    }
    x := 5
    made.pointer = &x
    if (made.pointer or_return 6)^ != 5 {
        return 6
    }
    // Formatted, None is none and Some its value
    storage : u8[64]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, "% %", declared, made.direct)
    if text_buffer.as_string(&text) != "none 7" {
        return 7
    }
    return 42
}
