package c_strings

import c_string from "std"
import testing from "std"

/*
 * std's c_string: a cstring's length and its text as a string, looking no further than a limit for its zero byte,
 * and None when it isn't there.
 */

finds_the_zero_within_the_limit #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    greeting : cstring = "hello"
    length :: c_string.length(greeting, 64)
    testing.expect_eq(t, length, cast[usize?](5), "a literal ends in a zero after its five letters")
    text :: c_string.to_string(greeting, 64)
    testing.expect_eq(t, text, cast[string?]("hello"), "the text is the bytes before the zero")
    // Exactly as long as the limit, which holds the zero
    exact :: c_string.length(greeting, 6)
    testing.expect_eq(t, exact, cast[usize?](5), "a limit of six bytes still reaches the zero")
    return .Ok
}

gives_none_without_a_zero_within_the_limit #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    greeting : cstring = "hello"
    testing.expect_none(t, c_string.length(greeting, 5), "the zero is the sixth byte, past a limit of five")
    testing.expect_none(t, c_string.to_string(greeting, 3), "the zero is past a limit of three")
    unterminated : u8[4] = u8.[1, 2, 3, 4]
    testing.expect_none(t, c_string.length(bit_cast[cstring](&unterminated), 4), "none of the four bytes is zero")
    return .Ok
}
