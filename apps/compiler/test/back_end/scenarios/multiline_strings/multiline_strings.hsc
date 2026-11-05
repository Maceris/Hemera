/*
 * Multiline strings (docs/types.md, Strings): each line's text after its \\, as it's written, joined by
 * newlines, with none after the last.
 */
package multiline_strings

import testing from "std"

/** Three lines, the second starting with a space after its \\. */
GREETING : string : \\Hello there,
    \\ this is all one string,
    \\over three lines.

/** Escapes aren't worked out: what's written is what's there, and an empty last line ends the one before. */
RAW : string :
    \\a\n"b"
    \\

joins_lines_with_newlines #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, GREETING, "Hello there,\n this is all one string,\nover three lines.",
        "the lines are joined by newlines, each kept from just after its \\\\")
    testing.expect_eq(t, GREETING.count, 55, "two newlines between three lines, and none after the last")
    local : string : \\one
        \\two
    testing.expect_eq(t, local, "one\ntwo", "a constant declared in a function is joined the same way")
    single : string : \\just one line
    testing.expect_eq(t, single, "just one line", "one line has no newline at all")
    return .Ok
}

keeps_escapes_as_written #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, RAW, "a\\n\"b\"\n", "a backslash and quotes are kept, and the empty last line gives a newline")
    return .Ok
}

knows_a_constant_strings_count #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // The bounds prover knows a constant string's count from its lines, so this needs no check
    testing.expect_eq(t, GREETING[54], '.', "the last of the 55 bytes ends the last line")
    return .Ok
}
