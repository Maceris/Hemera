package c_string

/*
 * How many bytes come before text's zero byte, looking at no more than limit of them: None if there's no zero among
 * them, so text that isn't what it should be, unterminated or not text at all, isn't read on past where it could end.
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

/*
 * text as a string, without its zero byte, looking at no more than limit bytes for it: None if there's no zero among
 * them. It refers to text's bytes rather than copying them.
 */
to_string :: fn(text: cstring, limit: usize) -> string? {
    count :: length(text, limit) or_return null
    return string_of(bit_cast[ptr[u8]](text), count)
}
