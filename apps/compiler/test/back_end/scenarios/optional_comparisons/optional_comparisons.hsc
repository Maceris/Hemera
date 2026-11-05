/*
 * Two optionals compared with == and != (docs/types.md, Optionals): equal when both hold nothing, or both hold values
 * that are equal.
 */
package optional_comparisons

import testing from "std"

/**
 * Find text, as a lookup that may come up empty would.
 *
 * @param text Any text.
 * @return The text itself; none when it's empty.
 */
found :: fn(text: string) -> string? {
    if text.count == 0 {
        return null
    }
    return text
}

compares_optional_numbers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    five : u64? = 5
    other_five : u64? = 5
    six : u64? = 6
    none : u64? = null
    other_none : u64? = null
    testing.expect(t, five == other_five && !(five != other_five), "two optionals holding equal values are equal")
    testing.expect(t, five != six && !(five == six), "two optionals holding different values differ")
    testing.expect(t, five != none && none != five, "one holding a value differs from one holding nothing, either way round")
    testing.expect(t, none == other_none && !(none != other_none), "two holding nothing are equal")
    return .Ok
}

compares_optional_strings #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, found("abc") == found("abc") && found("abc") != found("abd"), "strings held compare by their bytes")
    testing.expect(t, found("") == found("") && found("") != found("abc"), "two empty finds are equal, and differ from a found string")
    return .Ok
}
