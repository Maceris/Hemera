package raw

/*
 * How an array view and a string are laid out: the count, then the address of the first element.
 */
//TODO(claude) a builtin for a view from an address and a count, so this doesn't rely on the layout
ViewParts :: struct {
    count : usize,
    data : rawptr,
}

#assert size_of(ViewParts) == size_of(u8[])

// A view of count elements starting at data. The caller makes sure they're all there.
view_of :: fn[T](data: ptr[T], count: usize) -> T[] {
    return bit_cast[T[]](ViewParts.{count, cast[rawptr](data)})
}

// The text of count bytes starting at data.
string_of :: fn(data: ptr[u8], count: usize) -> string {
    return bit_cast[string](ViewParts.{count, cast[rawptr](data)})
}

// How many bytes come before the first zero byte at or after data.
c_string_length :: fn(data: ptr[u8]) -> usize {
    count : usize = 0
    loop {
        count += 1
    }
    while cast[ptr[u8]](cast[usize](data) + count)^ != 0
    return count
}

// The text of a zero-terminated string, without the zero. Empty for a null address.
string_of_c_string :: fn(data: rawptr) -> string {
    if data == null {
        return ""
    }
    bytes :: cast[ptr[u8]](data)
    return string_of(bytes, c_string_length(bytes))
}
