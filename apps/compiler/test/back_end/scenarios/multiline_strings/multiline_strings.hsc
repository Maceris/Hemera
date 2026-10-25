/*
 * Multiline strings (docs/types.md, Strings): each line's text after its \\, as it's written, joined by
 * newlines, with none after the last. main returns 42 if they all came out that way, or the number of the
 * first that didn't.
 */
package multiline_strings

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

GREETING : string : \\Hello there,
    \\ this is all one string,
    \\over three lines.

// Escapes aren't worked out: what's written is what's there
RAW : string :
    \\a\n"b"
    \\

main :: fn() -> int {
    errors := 0
    errors += check(GREETING == "Hello there,\n this is all one string,\nover three lines.", 1)
    errors += check(GREETING.count == 55, 2)
    errors += check(RAW == "a\\n\"b\"\n", 3)
    local : string : \\one
        \\two
    errors += check(local == "one\ntwo", 4)
    // The bounds prover knows a constant string's count from its lines
    errors += check(GREETING[54] == '.', 5)
    single : string : \\just one line
    errors += check(single == "just one line", 6)
    if errors == 0 {
        return 42
    }
    return errors
}
