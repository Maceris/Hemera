package c_strings

import c_string from "std"

/*
 * std's c_string: a cstring's length and its text as a string, looking no further than a limit for its zero byte,
 * and None when it isn't there. main returns 42 if each finds what it should.
 */

main :: fn() -> int {
    greeting : cstring = "hello"
    if (c_string.length(greeting, 64) or_return 1) != 5 {
        return 2
    }
    text :: c_string.to_string(greeting, 64) or_return 3
    if text != "hello" {
        return 4
    }
    // Exactly as long as the limit, which holds the zero
    if (c_string.length(greeting, 6) or_return 5) != 5 {
        return 6
    }
    // No zero within the limit
    if (c_string.length(greeting, 5) is_some) || (c_string.to_string(greeting, 3) is_some) {
        return 7
    }
    unterminated : u8[4] = u8.[1, 2, 3, 4]
    if c_string.length(bit_cast[cstring](&unterminated), 4) is_some {
        return 8
    }
    return 42
}
