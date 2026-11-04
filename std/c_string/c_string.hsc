package c_string

/**
 * Count the bytes before a C string's zero byte, looking at no more than a limit of them.
 *
 * The limit means text that isn't what it should be, unterminated or not text at all, isn't read on past where it
 * could end.
 *
 * @param text The C string, which must be readable for limit bytes or up to its zero byte, whichever comes first.
 * @param limit The most bytes to look at, in bytes.
 * @return How many bytes come before the zero byte, below limit; null if there's no zero among the first limit bytes.
 */
length :: fn(text: cstring, limit: usize) -> usize? {
    bytes :: bit_cast[ptr[u8]](text)
    for count in cast[usize](0)..<limit {
        if cast[ptr[u8]](cast[usize](bytes) + count)^ == 0 {
            return count
        }
    }
    return null
}

/**
 * View a C string as a string, without its zero byte, looking at no more than a limit of bytes for it.
 *
 * @param text The C string, which must be readable for limit bytes or up to its zero byte, whichever comes first.
 * @param limit The most bytes to look at for the zero byte.
 * @return A string over text's bytes rather than a copy, good as long as they are; null if there's no zero among the
 *     first limit bytes.
 */
to_string :: fn(text: cstring, limit: usize) -> string? {
    count :: length(text, limit) or_return null
    return string_of(bit_cast[ptr[u8]](text), count)
}
