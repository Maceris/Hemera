/*
 * Optionals that start zeroed are None (docs/types.md, Optional Types): left out of a struct's literal, in an array of
 * structs, declared without a value, an optional pointer too; and None and Some still behave and format as before.
 */
package optional_defaults

import testing from "std"
import text_buffer from "std"

/** A struct holding only an optional. */
Inner :: struct {
    /** None until it's given one. */
    value : u32?,
}

/** Optionals held directly, in a struct, in an array of structs, and of a pointer. */
Outer :: struct {
    /** None until it's given one. */
    direct : u32?,
    /** Its optional none until it's given one. */
    nested : Inner,
    /** Each one's optional none until it's given one. */
    many : Inner[4],
    /** None until it's given one. */
    pointer : ptr[int]?,
    /** Any value. */
    count : int,
}

/**
 * Halve a number, if it's even.
 *
 * @param n Any number.
 * @return n / 2; none when n is odd.
 */
half :: fn(n: u32) -> u32? {
    if n % 2 != 0 {
        return null
    }
    return n / 2
}

starts_optionals_as_none #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    made := Outer.{count = 1}
    testing.expect(t, made.direct is_none, "an optional left out of a literal is none")
    testing.expect(t, made.nested.value is_none, "an optional in a struct left out of a literal is none")
    testing.expect(t, made.many[2].value is_none, "an optional in an array of structs left out of a literal is none")
    testing.expect(t, made.pointer is_none, "an optional pointer left out of a literal is none")
    plain : Outer
    declared : u32?
    testing.expect(t, plain.direct is_none, "an optional in a struct declared without a value is none")
    testing.expect(t, plain.many[1].value is_none, "so is one in its array of structs")
    testing.expect(t, (declared is_none) && declared == null, "an optional declared without a value is none, equal to null")
    return .Ok
}

keeps_some_and_none_working #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, half(4) or_else 0, 2, "or_else gives the value held")
    testing.expect(t, half(3) is_none, "an odd number has no half")
    testing.expect(t, half(6) == 3, "an optional holding 3 equals 3")
    match half(8) {
        case Some(n) => testing.expect_eq(t, n, 4, "match binds the value held")
        case None => testing.fail(t, "8 has a half")
    }
    made := Outer.{count = 1}
    made.direct = 7
    testing.expect(t, made.direct == 7 && made.direct != null, "an optional given a value holds it")
    x := 5
    made.pointer = &x
    pointer :: testing.require_some(t, made.pointer, "an optional pointer given an address holds it")?
    testing.expect_eq(t, pointer^, 5, "it points at what it was given")
    return .Ok
}

formats_none_and_some #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    declared : u32?
    given : u32? = 7
    storage : u8[64]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, "% %", declared, given)
    testing.expect_eq(t, text_buffer.as_string(&text), "none 7", "None formats as none and Some as its value")
    return .Ok
}
