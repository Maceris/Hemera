package c_string

// How many bytes come before text's zero byte.
length :: fn(text: cstring) -> usize {
    bytes :: bit_cast[ptr[u8]](text)
    count : usize = 0
    loop {
        if cast[ptr[u8]](cast[usize](bytes) + count)^ == 0 {
            return count
        }
        count += 1
    }
}

// text as a string, without its zero byte. It refers to text's bytes rather than copying them.
to_string :: fn(text: cstring) -> string {
    return string_of(bit_cast[ptr[u8]](text), length(text))
}
