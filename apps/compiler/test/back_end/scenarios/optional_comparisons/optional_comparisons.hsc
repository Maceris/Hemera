/*
 * Two optionals compared with == and != (docs/types.md, Optionals): equal when both hold nothing, or both hold values
 * that are equal. main returns 42 if they all held, or the number of the first that didn't.
 */
package optional_comparisons

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

found :: fn(text: string) -> string? {
    if text.count == 0 {
        return null
    }
    return text
}

main :: fn() -> int {
    five : u64? = 5
    other_five : u64? = 5
    six : u64? = 6
    none : u64? = null
    other_none : u64? = null
    errors := 0
    errors += check(five == other_five && !(five != other_five), 1)
    errors += check(five != six && !(five == six), 2)
    errors += check(five != none && none != five, 3)
    errors += check(none == other_none && !(none != other_none), 4)
    errors += check(found("abc") == found("abc") && found("abc") != found("abd"), 5)
    errors += check(found("") == found("") && found("") != found("abc"), 6)
    if errors == 0 {
        return 42
    }
    return errors
}
